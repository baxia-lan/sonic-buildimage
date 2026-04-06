"""Macros for building OCI layer tars via Docker containers.

These genrule wrappers execute apt-get and dpkg operations inside Docker
containers, enabling the build to work on both Linux and macOS.
"""

# Pin by digest for reproducibility. Refresh: crane digest debian:bookworm-slim
_DEBIAN_IMAGE = "debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a"

# Snapshot mirror for reproducible apt installs.
_APT_SNAPSHOT_URL = "https://snapshot.debian.org/archive/debian/20260401T000000Z"

def apt_install_layer(
        name,
        packages,
        pip_packages = [],
        post_install_cmds = [],
        size_budget_mb = 0,
        visibility = None):
    """Create an OCI layer tar by installing apt packages in a Docker container.

    Args:
        name:             Target name. Output: <name>.tar
        packages:         List of apt package names to install.
        pip_packages:     List of pip packages to install.
        post_install_cmds: Shell commands to run after install (cleanup, strip, etc).
        size_budget_mb:   If > 0, fail if layer exceeds this size.
        visibility:       Bazel visibility.
    """
    pip_cmd = ""
    if pip_packages:
        pip_cmd = "pip3 install --break-system-packages --no-cache-dir %s" % " ".join(pip_packages)

    post_cmds = "\n    ".join(post_install_cmds) if post_install_cmds else ""

    size_check = ""
    if size_budget_mb > 0:
        size_check = """
    SIZE_MB=$$(( $$(wc -c < /output/layer.tar) / 1048576 ))
    if [ "$$SIZE_MB" -gt {budget} ]; then
      echo "FAIL: {name} is $$SIZE_MB MB, exceeds {budget} MB budget"
      exit 1
    fi
    echo "{name}: $$SIZE_MB MB (budget: {budget} MB)"
""".format(name = name, budget = size_budget_mb)

    native.genrule(
        name = name,
        srcs = [],
        outs = [name + ".tar"],
        cmd = """
set -euo pipefail
OUT=$$(cd $$(dirname $(OUTS)) && pwd)/$$(basename $(OUTS))
mkdir -p $$(dirname "$$OUT")
touch "$$OUT"

docker run --rm \
  -v "$$OUT:/output/layer.tar" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e SOURCE_DATE_EPOCH=0 \
  {image} \
  bash -euo pipefail -c '
    echo "deb [check-valid-until=no] {snapshot_url} bookworm main" > /etc/apt/sources.list
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends {packages}
    {pip_cmd}
    # Strip debug symbols
    find / -name "*.so*" -type f -exec strip --strip-debug {{}} \\; 2>/dev/null || true
    # Remove docs/man/locale
    rm -rf /usr/share/man /usr/share/doc /usr/share/info \\
           /usr/share/locale /usr/share/i18n /usr/share/groff \\
           /usr/share/lintian /usr/share/bash-completion \\
           /var/cache/man /var/cache/apt /var/lib/apt/lists 2>/dev/null || true
    find / -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true
    {post_cmds}
    SOURCE_DATE_EPOCH=0 tar \\
      --sort=name --mtime=@0 --owner=0 --group=0 \\
      --exclude=./proc --exclude=./sys --exclude=./dev \\
      --exclude=./output --exclude=./var/cache \\
      --exclude=./var/lib/apt --exclude=./run \\
      -C / -cf /output/layer.tar .
    {size_check}
  '
""".format(
            image = _DEBIAN_IMAGE,
            packages = " ".join(packages),
            pip_cmd = pip_cmd,
            post_cmds = post_cmds,
            size_check = size_check,
            snapshot_url = _APT_SNAPSHOT_URL,
        ),
        tags = ["requires-docker", "no-sandbox", "no-cache"],
        visibility = visibility,
    )

def deb_extract_layer(
        name,
        debs,
        strip = True,
        size_budget_mb = 0,
        visibility = None):
    """Create an OCI layer tar by extracting .deb files in a Docker container.

    Args:
        name:           Target name. Output: <name>.tar
        debs:           Labels of .deb file targets to extract.
        strip:          Whether to strip debug symbols from binaries.
        size_budget_mb: If > 0, fail if layer exceeds this size.
        visibility:     Bazel visibility.
    """
    strip_cmd = ""
    if strip:
        strip_cmd = 'find "$$ROOTFS" -name "*.so*" -type f | xargs -r strip --strip-debug 2>/dev/null || true'

    size_check = ""
    if size_budget_mb > 0:
        size_check = """
SIZE_MB=$$(( $$(wc -c < $(OUTS)) / 1048576 ))
if [ "$$SIZE_MB" -gt {budget} ]; then
  echo "FAIL: {name} is $$SIZE_MB MB, exceeds {budget} MB budget"
  exit 1
fi
""".format(name = name, budget = size_budget_mb)

    native.genrule(
        name = name,
        srcs = debs,
        outs = [name + ".tar"],
        cmd = """
set -euo pipefail
OUT=$$(cd $$(dirname $(OUTS)) && pwd)/$$(basename $(OUTS))
touch "$$OUT"

# Collect all input .deb files
DEBS=""
for src in $(SRCS); do
  case "$$src" in *.deb) DEBS="$$DEBS $$src" ;; esac
done

if [ -z "$$DEBS" ]; then
  # No .deb files — create empty tar
  tar -cf "$$OUT" --files-from /dev/null
  exit 0
fi

# Extract debs inside Docker (dpkg-deb needs Linux)
DEB_DIR=$$(mktemp -d)
for deb in $$DEBS; do
  cp "$$deb" "$$DEB_DIR/" 2>/dev/null || true
done

docker run --rm \
  -v "$$DEB_DIR:/debs:ro" \
  -v "$$OUT:/output/layer.tar" \
  -e SOURCE_DATE_EPOCH=0 \
  {image} \
  bash -euo pipefail -c '
    ROOTFS=$$(mktemp -d)
    for deb in /debs/*.deb; do
      [ -s "$$deb" ] && dpkg-deb -x "$$deb" "$$ROOTFS" 2>/dev/null || true
    done
    {strip_cmd}
    if [ -d "$$ROOTFS" ] && [ "$$(ls -A $$ROOTFS 2>/dev/null)" ]; then
      SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 --owner=0 --group=0 \\
        -C "$$ROOTFS" -cf /output/layer.tar .
    else
      tar -cf /output/layer.tar --files-from /dev/null
    fi
  '
rm -rf "$$DEB_DIR"
{size_check}
""".format(
            image = _DEBIAN_IMAGE,
            strip_cmd = strip_cmd,
            size_check = size_check,
        ),
        tags = ["requires-docker", "no-sandbox"],
        visibility = visibility,
    )
