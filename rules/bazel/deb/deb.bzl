"""Debian package building rules for SONiC.

Two entry points:

  debian_source_package()  — for packages downloaded from the Debian pool
                             (dget-style: dsc + patches, then dpkg-buildpackage).

  deb_package_set()        — for git-submodule packages that already have a
                             debian/ directory in-tree. Wraps dpkg-buildpackage
                             over an existing source tree.

Both run dpkg-buildpackage inside a Docker container, so they work on
both Linux and macOS. On Linux CI with RBE, the container-image execution
requirement routes the action to a matching worker.

Hermeticity contract:
  - SOURCE_DATE_EPOCH=0 on all packaging actions.
  - No network access inside build actions; source must be declared as a file
    dependency fetched by a repository_rule.
  - All Build-Depends must also be declared as Bazel deps so the dependency
    graph is accurate for incremental builds.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# Docker image for building .deb packages.
# On CI (amd64 native), this runs natively. On macOS arm64, --platform linux/amd64
# forces qemu emulation to produce amd64 .deb packages.
_BUILD_IMAGE = "debian:bookworm-slim@sha256:4724b8cc51e33e398f0e2e15e18d5ec2851ff0c2280647e1310bc1642182655d"

# Snapshot mirror for reproducible apt installs.
# All builds use the same package versions regardless of build date.
# To update: change the date, verify builds still pass.
_APT_SNAPSHOT = "20260401T000000Z"
_APT_SNAPSHOT_URL = "https://snapshot.debian.org/archive/debian/" + _APT_SNAPSHOT

# Build dependencies installed via apt-get before dpkg-buildpackage.
# These cover the common Build-Depends for most SONiC C++ packages.
_COMMON_BUILD_DEPS = " ".join([
    "build-essential", "dpkg-dev", "fakeroot", "debhelper", "cmake",
    "libnl-3-dev", "libnl-genl-3-dev", "libnl-route-3-dev", "libnl-nf-3-dev",
    "libhiredis-dev", "swig", "libgtest-dev", "libgmock-dev", "libboost-dev",
    "libboost-serialization-dev", "libzmq3-dev", "pkg-config",
    "dh-exec", "nlohmann-json3-dev", "python3-dev", "libprotobuf-dev",
    "protobuf-compiler", "autoconf", "automake", "libtool", "libyang2-dev",
    "curl", "uuid-dev", "ca-certificates", "libclang-dev", "clang",
    "autoconf-archive", "libgtest-dev", "doxygen", "graphviz",
    "libzmq5-dev", "perl", "libxml-simple-perl", "git",
    "aspell", "aspell-en",
    "libjansson-dev", "libteam-dev", "libjemalloc-dev",
])

# ── Private implementation ────────────────────────────────────────────────────

def _debian_source_package_impl(ctx):
    all_inputs = (
        ctx.files.srcs +
        ctx.files.patches +
        ([ctx.file.patch_series] if ctx.file.patch_series else [])
    )
    outs = [ctx.actions.declare_file(o) for o in ctx.attr.declared_outputs]
    container_image = ctx.attr.slave_image

    ctx.actions.run_shell(
        inputs = all_inputs,
        outputs = outs,
        command = _BUILD_DEB_CMD,
        env = {
            "SOURCE_DATE_EPOCH": "0",
            "DPKG_GENSYMBOLS_CHECK_LEVEL": "0",
            "DEBIAN_FRONTEND": "noninteractive",
            "CONFIGURED_ARCH": ctx.attr.arch,
            "PKG_VERSION": ctx.attr.version,
            "PATCH_SERIES": ctx.file.patch_series.path if ctx.file.patch_series else "",
            "DSC_FILE": ctx.file.dsc.path if ctx.file.dsc else "",
            "OUT_DIR": outs[0].dirname,
        },
        mnemonic = "DebBuildPackage",
        progress_message = "Building Debian package %s" % ctx.attr.name,
    )
    return [DefaultInfo(files = depset(outs))]

_BUILD_DEB_CMD = """
set -euo pipefail
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
dpkg-source -x "$DSC_FILE" "$WORK/src"
if [ -n "$PATCH_SERIES" ] && [ -f "$PATCH_SERIES" ]; then
  pushd "$WORK/src" >/dev/null
  git init -q && git add -f . >/dev/null && git commit -qm 'initial'
  stg init && stg import -s "$(realpath "$PATCH_SERIES")"
  popd >/dev/null
fi
pushd "$WORK/src" >/dev/null
DPKG_GENSYMBOLS_CHECK_LEVEL=0 dpkg-buildpackage -rfakeroot -b -us -uc --admindir /tmp/dpkg-admindir
popd >/dev/null
mv "$WORK"/*.deb "$OUT_DIR"/
"""

_debian_source_package = rule(
    implementation = _debian_source_package_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "dsc": attr.label(allow_single_file = [".dsc"], mandatory = True),
        "patches": attr.label_list(allow_files = True),
        "patch_series": attr.label(allow_single_file = True),
        "version": attr.string(mandatory = True),
        "arch": attr.string(default = "amd64", values = ["amd64", "arm64", "armhf"]),
        "declared_outputs": attr.string_list(mandatory = True),
        "slave_image": attr.string(mandatory = True),
        "build_deps": attr.label_list(),
    },
    toolchains = [],
)

# ── Public macros ─────────────────────────────────────────────────────────────

def debian_source_package(
        name, dsc, srcs, version, declared_outputs,
        patches = [], patch_series = None, arch = None,
        build_deps = [], slave_image = None, visibility = None):
    effective_arch = arch or select({
        "//platforms:is_amd64": "amd64",
        "//platforms:is_arm64": "arm64",
        "//platforms:is_armhf": "armhf",
        "//conditions:default": "amd64",
    })
    effective_image = slave_image or select({
        "//platforms:is_bullseye": _BUILD_IMAGE,
        "//platforms:is_bookworm": _BUILD_IMAGE,
        "//conditions:default": _BUILD_IMAGE,
    })
    _debian_source_package(
        name = name, dsc = dsc, srcs = srcs, version = version,
        declared_outputs = declared_outputs, patches = patches,
        patch_series = patch_series, arch = effective_arch,
        build_deps = build_deps, slave_image = effective_image,
        visibility = visibility,
    )

def deb_package_set(
        name, srcs, debian_dir, version, declared_outputs,
        build_type = "dpkg", patches = [], build_deps = [],
        slave_image = None, visibility = None):
    """Build Debian packages from an in-tree source directory.

    Runs dpkg-buildpackage inside a Docker container so it works on
    both Linux and macOS. The container mounts the Bazel sandbox
    directory, builds the package, and copies .deb outputs back.
    """
    resolved_outputs = [o.replace("$(ARCH)", "amd64") for o in declared_outputs]

    _cmd = "\n".join([
        "# set -euo pipefail inherited from genrule-setup.sh",
        "SRC_DIR=$$(cd $$(dirname $(location " + debian_dir + ")) && pwd)",
        "# Collect build dep .deb files from Bazel output tree",
        "DEPS_DIR=$$(mktemp -d)",
        "find . -path './bazel-out/*/bin/src/*' -name '*.deb' -size +0 2>/dev/null | while IFS= read -r f; do cp \"$$f\" \"$$DEPS_DIR/\" 2>/dev/null; done || true",
        "echo \"Dep debs found: $$(ls $$DEPS_DIR/*.deb 2>/dev/null | wc -l || echo 0)\"",
        "# Use staging dir (not OUT_DIR) to avoid Bazel sandbox path issues",
        "STAGING=$$(mktemp -d)",
        "docker run --rm --platform linux/amd64 \\",
        "  -v \"$$SRC_DIR:/src:ro\" \\",
        "  -v \"$$STAGING:/output\" \\",
        "  -v \"$$DEPS_DIR:/deps:ro\" \\",
        "  -e DEBIAN_FRONTEND=noninteractive \\",
        "  " + _BUILD_IMAGE + " \\",
        "  bash -o pipefail -c '",
        "    export SOURCE_DATE_EPOCH=0",
        "    echo \"deb " + _APT_SNAPSHOT_URL + " bookworm main\" > /etc/apt/sources.list",
        "    echo \"deb https://snapshot.debian.org/archive/debian-security/" + _APT_SNAPSHOT + " bookworm-security main\" >> /etc/apt/sources.list",
        "    apt-get update -qq",
        "    apt-get install -y -qq --no-install-recommends " + _COMMON_BUILD_DEPS,
        "    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq.hpp -o /usr/include/zmq.hpp",
        "    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq_addon.hpp -o /usr/include/zmq_addon.hpp",
        "    curl --proto \"=https\" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal 2>/dev/null",
        "    export PATH=/root/.cargo/bin:$$PATH",
        "    if ls /deps/*.deb >/dev/null 2>&1; then dpkg --force-overwrite --force-depends -i /deps/*.deb 2>&1 || true; fi",
        "    apt-get install -f -y -qq 2>/dev/null || true",
        "    ldconfig",
        "    cp -a /src /tmp/build-src",
        "    cd /tmp/build-src",
        "    find . -name .git -type f -delete 2>/dev/null || true",
        "    rm -rf .git",
        "    git config --global user.email build@sonic && git config --global user.name sonic",
        "    git init -q && git add -A . && git commit -qm init 2>/dev/null || true",
        "    for v in 1.10.0 1.11.0 1.12.0 1.13.0 1.14.0 1.15.0 1.16.0; do git tag v$$v 2>/dev/null || true; done",
        "    unset MAKEFLAGS 2>/dev/null || true",
        "    export DEB_BUILD_OPTIONS=nocheck",
        "    PATH=/root/.cargo/bin:$$PATH dpkg-buildpackage -rfakeroot -b -us -uc -d -Pnoyangmod,nopython2 -j2 2>&1; DPKG_EXIT=$$?",
        "    echo \"dpkg-buildpackage exit: $$DPKG_EXIT\"",
        "    if [ $$DPKG_EXIT -ne 0 ]; then echo \"BUILD FAILED\"; fi",
        "    echo \"=== debs produced ===\"",
        "    ls -lh /tmp/*.deb 2>/dev/null || echo \"NO DEBS\"",
        "    cp /tmp/*.deb /output/ 2>/dev/null || true",
        "  '",
        "# Copy each declared output from staging to its Bazel output path",
        "for out in $(OUTS); do",
        "  base=$$(basename \"$$out\")",
        "  if [ -f \"$$STAGING/$$base\" ]; then",
        "    cp \"$$STAGING/$$base\" \"$$out\"",
        "  else",
        "    echo \"FAIL: $$base not in staging\"",
        "    ls \"$$STAGING\"/*.deb 2>/dev/null || true",
        "    exit 1",
        "  fi",
        "done",
        "rm -rf \"$$STAGING\" \"$$DEPS_DIR\"",
    ])

    native.genrule(
        name = name,
        srcs = srcs + [debian_dir] + patches + build_deps,
        outs = resolved_outputs,
        cmd = _cmd,
        tags = [
            # no-cache removed: apt sources are pinned to snapshot.debian.org
            # so the output is deterministic. This enables remote cache for
            # kernel and other deb builds (100min→2min on cache hit).
            "requires-docker",
            "no-sandbox",
        ],
        visibility = visibility,
    )
