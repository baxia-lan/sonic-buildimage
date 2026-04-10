"""Builds a SONiC OCI Docker image from Debian packages and config files.

Wraps ``rules_oci`` ``oci_image`` to assemble an OCI image that mirrors the
layout of a classic SONiC Docker container.  Debian ``.deb`` files are
installed via a ``dpkg`` layer, Python wheels via pip, and configuration
files are placed at their target paths inside the image.

All inputs are hermetic Bazel targets — no Docker daemon is required.

Args:
    name: Unique target name.  Produces ``<name>`` (oci_image) and
        ``<name>_tarball`` (oci_load) targets.
    base: Label of the base OCI image (e.g. ``"//docker/base-trixie"``
        or ``"@debian_bookworm"``).
    apt_packages: List of ``@bookworm//<pkg>:data`` labels whose extracted
        tarballs are layered directly into the image.  These are system
        packages resolved by rules_distroless (files go to correct paths).
        Use the ``:data`` suffix to get the extracted filesystem tree.
    debs: List of ``.deb`` labels (typically ``sonic_deb_package`` targets)
        staged to ``/var/cache/sonic/debs`` for runtime installation.
    python_wheels: List of Python wheel labels staged to
        ``/var/cache/sonic/wheels``.
    configs: Dictionary mapping destination path (string) to source label.
        Each entry places the source file at the given absolute path inside
        the container (e.g. ``{"/etc/sonic/config.json": "//src:config"}``).
    scripts: Dictionary mapping destination path to source label for
        executable scripts (e.g. init scripts).  Like ``configs`` but
        the files are marked executable.
    env: Dictionary of environment variables set in the image config.
    entrypoint: Entrypoint command list.  Defaults to ``["/usr/bin/bash"]``.
    cmd: Default command list appended after the entrypoint.

Returns:
    ``DefaultInfo`` from ``oci_image`` — an OCI image directory.

Example:
    ```starlark
    load("//tools/docker:defs.bzl", "sonic_docker_image")

    sonic_docker_image(
        name = "docker-database",
        base = "//docker/config-engine-trixie",
        apt_packages = [
            "@bookworm//redis-server:data",
            "@bookworm//redis-tools:data",
        ],
        debs = [
            "@sonic_swss_common//:libswsscommon",
        ],
        configs = {
            "/usr/share/sonic/templates/supervisord.conf.j2": "supervisord.conf.j2",
            "/usr/share/sonic/templates/database_config.json.j2": "database_config.json.j2",
        },
        scripts = {
            "/usr/local/bin/docker-database-init.sh": "docker-database-init.sh",
        },
        env = {"DEBIAN_FRONTEND": "noninteractive"},
        entrypoint = ["/usr/local/bin/docker-database-init.sh"],
    )
    ```
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

# ── Slim genrule shell command ────────────────────────────────────────────────
# Merges a list of @bookworm :data tarballs into one filtered tarball.
# Optimisations applied:
#   1. ELF binary symbol stripping (strip --strip-unneeded)
#   2. Locale pruning — keep only en_US.UTF-8
#   3. Man-page removal (/usr/share/man)
#   4. Documentation removal (/usr/share/doc)
#   5. Python bytecode cache removal (__pycache__, *.pyc, *.pyo)
#
# The command is intentionally defensive (|| true) so that:
#   • macOS sandboxes work: macOS strip(1) cannot strip ELF, fails silently.
#   • Packages that lack a given directory are handled without error.
_SLIM_CMD = """\
set -euo pipefail
TMPDIR=$$(mktemp -d)
cleanup() { rm -rf "$$TMPDIR"; }
trap cleanup EXIT

# 1. Extract all apt package tarballs into a staging directory.
for src in $(SRCS); do
    tar xf "$$src" -C "$$TMPDIR" 2>/dev/null || true
done

# 2. Strip ELF binaries (--strip=always equivalent for pre-built packages).
#    Gracefully skipped on macOS where strip(1) handles Mach-O, not ELF.
if command -v strip >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
    find "$$TMPDIR" -type f | while IFS= read -r f; do
        if file "$$f" 2>/dev/null | grep -q " ELF "; then
            strip --strip-unneeded "$$f" 2>/dev/null || true
        fi
    done
fi

# 3. Remove locale data — keep only en_US.UTF-8 and locale.alias.
#    Typical saving: 20-35 MB per image.
if [ -d "$$TMPDIR/usr/share/locale" ]; then
    find "$$TMPDIR/usr/share/locale" -mindepth 1 -maxdepth 1 \\
        ! -name "en_US.UTF-8" ! -name "locale.alias" -exec rm -rf {} + 2>/dev/null || true
fi

# 4. Remove man pages (~5-10 MB).
rm -rf "$$TMPDIR/usr/share/man"

# 5. Remove package documentation (~10-20 MB).
rm -rf "$$TMPDIR/usr/share/doc"

# 6. Remove Python bytecode caches (~1-3 MB).
find "$$TMPDIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$$TMPDIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$$TMPDIR" -type f -name "*.pyo" -delete 2>/dev/null || true

# 7. Repack filtered contents into a single output tarball.
#    Use COPYFILE_DISABLE=1 to prevent macOS BSD tar from embedding
#    AppleDouble/xattr PAX headers (com.apple.provenance) which break docker load.
COPYFILE_DISABLE=1 tar cf "$@" -C "$$TMPDIR" .
"""

def slim_apt_layer(name, srcs, visibility = None):
    """Merges @bookworm apt package tarballs into one stripped, slimmed layer.

    Applies the full set of image-size optimisations defined in ``_SLIM_CMD``:
    ELF symbol stripping, locale pruning (en_US.UTF-8 only), man/doc removal,
    and ``__pycache__`` / ``*.pyc`` cleanup.

    This function is used internally by ``sonic_docker_image`` when
    ``slim = True`` (the default), and can also be called directly from
    ``BUILD.bazel`` files that assemble images with raw ``oci_image``.

    Args:
        name: Unique target name.  Produces a ``<name>.tar`` output.
        srcs: List of ``@bookworm//<pkg>:data`` labels (extracted package tarballs).
        visibility: Bazel visibility list.

    Example:
        ```starlark
        load("//tools/docker:defs.bzl", "slim_apt_layer")

        slim_apt_layer(
            name = "base_slim",
            srcs = [
                "@bookworm//curl:data",
                "@bookworm//iproute2:data",
            ],
            visibility = ["//visibility:private"],
        )
        ```
    """
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [name + ".tar"],
        cmd = _SLIM_CMD,
        visibility = visibility or ["//visibility:private"],
    )

def sonic_docker_image(
        name,
        base,
        apt_packages = [],
        debs = [],
        python_wheels = [],
        configs = {},
        scripts = {},
        env = {},
        entrypoint = ["/usr/bin/bash"],
        cmd = [],
        visibility = None,
        slim = True,
        **kwargs):
    """Assembles a SONiC Docker image as an OCI artefact.

    Creates a multi-layer OCI image following the one-layer-per-concern
    principle:
      1. Base image layer (system root).
      2. Apt packages layer (``apt_packages`` — extracted @bookworm tarballs,
         optionally slimmed: ELF stripped, locale/man/doc/__pycache__ removed).
      3. Debian packages layer (``debs`` — staged to /var/cache/sonic/debs).
      4. Python wheels layer (``python_wheels`` — staged to /var/cache/sonic/wheels).
      5. Scripts layer (``scripts`` — executable files at target paths).
      6. Configuration files layer (``configs`` — at target paths).

    Symbol stripping for source-built binaries is handled via
    ``build:opt --strip=always`` in ``.bazelrc``.  Pre-built apt package
    binaries are stripped inside the ``slim_apt_layer`` genrule.

    Args:
        name: Target name.
        base: Base OCI image label.
        apt_packages: @bookworm package tarball labels (proper system install).
        debs: .deb package labels (staged for runtime install).
        python_wheels: Python wheel labels (staged for runtime install).
        configs: Dict of {container_path: source_label} for config files.
        scripts: Dict of {container_path: source_label} for executable scripts.
        env: Dict of environment variables.
        entrypoint: Image entrypoint command.
        cmd: Default command.
        visibility: Bazel visibility.
        slim: When ``True`` (default), apt package tarballs are merged and
            filtered through ``slim_apt_layer``: ELF symbols stripped, locales
            pruned to en_US.UTF-8, man/doc directories and Python bytecode
            caches removed.  Pass ``False`` only for test/dev images that need
            the full package contents.
        **kwargs: Forwarded to ``oci_image``.
    """

    tars = []

    # ── Layer 1: Apt packages (extracted tarballs at correct paths) ─────
    # @bookworm packages from rules_distroless are pre-extracted tarballs.
    # When slim=True, all apt tarballs are merged and filtered via
    # slim_apt_layer() before being passed to oci_image.  This:
    #   - Strips ELF binary symbols (~20-40% per binary)
    #   - Removes locale data except en_US.UTF-8 (~25 MB)
    #   - Removes /usr/share/man and /usr/share/doc (~15 MB)
    #   - Removes __pycache__ and *.pyc files (~2 MB)
    if slim and apt_packages:
        slim_apt_layer(
            name = name + "_slim_apt",
            srcs = list(apt_packages),
            visibility = ["//visibility:private"],
        )
        apt_tars = [":" + name + "_slim_apt"]
    else:
        apt_tars = list(apt_packages)  # copy so we don't mutate caller's list

    # ── Layer 2: Debian packages (staged) ──────────────────────────────
    if debs:
        pkg_tar(
            name = name + "_debs_layer",
            srcs = debs,
            package_dir = "/var/cache/sonic/debs",
            visibility = ["//visibility:private"],
        )
        tars.append(name + "_debs_layer")

    # ── Layer 3: Python wheels (staged) ──────────────────────────────────
    if python_wheels:
        pkg_tar(
            name = name + "_wheels_layer",
            srcs = python_wheels,
            package_dir = "/var/cache/sonic/wheels",
            visibility = ["//visibility:private"],
        )
        tars.append(name + "_wheels_layer")

    # ── Layer 4: Scripts (executable files) ──────────────────────────────
    if scripts:
        _script_tars = []
        for i, (dest_path, src_label) in enumerate(scripts.items()):
            _tar_name = name + "_script_%d" % i
            pkg_tar(
                name = _tar_name,
                srcs = [src_label],
                package_dir = "/".join(dest_path.split("/")[:-1]),
                mode = "0755",
                visibility = ["//visibility:private"],
            )
            _script_tars.append(_tar_name)

        if _script_tars:
            pkg_tar(
                name = name + "_scripts_layer",
                deps = [":" + t for t in _script_tars],
                visibility = ["//visibility:private"],
            )
            tars.append(name + "_scripts_layer")

    # ── Layer 5: Configuration files ─────────────────────────────────────
    if configs:
        _cfg_tars = []
        for i, (dest_path, src_label) in enumerate(configs.items()):
            _tar_name = name + "_cfg_%d" % i
            pkg_tar(
                name = _tar_name,
                srcs = [src_label],
                package_dir = "/".join(dest_path.split("/")[:-1]),
                visibility = ["//visibility:private"],
            )
            _cfg_tars.append(_tar_name)

        if _cfg_tars:
            pkg_tar(
                name = name + "_configs_layer",
                deps = [":" + t for t in _cfg_tars],
                visibility = ["//visibility:private"],
            )
            tars.append(name + "_configs_layer")

    # ── OCI image ──────────────────────────────────────────────────────
    # Combine apt tarballs (string labels) with locally-built layers
    # (colon-prefixed local targets).
    all_tars = apt_tars + [":" + t for t in tars]

    oci_image(
        name = name,
        base = base,
        tars = all_tars if all_tars else [],
        env = env if env else None,
        entrypoint = entrypoint if entrypoint else None,
        cmd = cmd if cmd else None,
        visibility = visibility,
        **kwargs
    )

    # ── Convenience tarball for docker-load ────────────────────────────
    oci_load(
        name = name + "_tarball",
        image = ":" + name,
        repo_tags = ["sonic/" + name + ":latest"],
        visibility = visibility,
    )
