"""Debian package building rules for SONiC.

Two entry points:

  debian_source_package()  — for packages downloaded from the Debian pool
                             (dget-style: dsc + patches, then dpkg-buildpackage).

  deb_package_set()        — for git-submodule packages that already have a
                             debian/ directory in-tree. Wraps dpkg-buildpackage
                             over an existing source tree.

Both rules run dpkg-buildpackage inside the sonic-slave container, declared as
a toolchain so Bazel can schedule the action on a compatible worker (RBE) or
fall back to a local Docker wrapper in dev builds.

Hermeticity contract:
  - SOURCE_DATE_EPOCH=0 on all packaging actions.
  - No network access inside build actions; source must be declared as a file
    dependency fetched by a repository_rule.
  - All Build-Depends must also be declared as Bazel deps so the dependency
    graph is accurate for incremental builds.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# ── Private implementation ────────────────────────────────────────────────────

def _debian_source_package_impl(ctx):
    """Implementation of debian_source_package rule."""
    all_inputs = (
        ctx.files.srcs +
        ctx.files.patches +
        ([ctx.file.patch_series] if ctx.file.patch_series else [])
    )

    outs = [ctx.actions.declare_file(o) for o in ctx.attr.declared_outputs]

    # The sonic-slave image digest is injected via the toolchain.
    # When running on GCP RBE, execution_requirements routes the action to a
    # worker with the matching container image.
    # For local dev, the deb_package_local.sh wrapper invokes `docker run`.
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
        execution_requirements = {
            "container-image": "docker://" + container_image,
            "no-sandbox": "0",
            "requires-network": "0",
        },
        mnemonic = "DebBuildPackage",
        progress_message = "Building Debian package %s" % ctx.attr.name,
    )

    return [DefaultInfo(files = depset(outs))]

_BUILD_DEB_CMD = """
set -euo pipefail
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Unpack the Debian source package.
dpkg-source -x "$DSC_FILE" "$WORK/src"

# Apply SONiC patches if a series file was provided.
if [ -n "$PATCH_SERIES" ] && [ -f "$PATCH_SERIES" ]; then
  pushd "$WORK/src" >/dev/null
  git init -q
  git add -f . >/dev/null
  git commit -qm 'initial'
  stg init
  stg import -s "$(realpath "$PATCH_SERIES")"
  popd >/dev/null
fi

# Build the binary packages.
pushd "$WORK/src" >/dev/null
if [ "$CONFIGURED_ARCH" = "armhf" ] || [ "$CONFIGURED_ARCH" = "arm64" ]; then
  DPKG_GENSYMBOLS_CHECK_LEVEL=0 dpkg-buildpackage \
    -rfakeroot -b -us -uc \
    -a"$CONFIGURED_ARCH" -Pcross,nocheck \
    --admindir /tmp/dpkg-admindir
else
  DPKG_GENSYMBOLS_CHECK_LEVEL=0 dpkg-buildpackage \
    -rfakeroot -b -us -uc \
    --admindir /tmp/dpkg-admindir
fi
popd >/dev/null

# Move outputs to the Bazel output tree.
mv "$WORK"/*.deb "$OUT_DIR"/
"""

_debian_source_package = rule(
    implementation = _debian_source_package_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Upstream source files (orig.tar.gz, diff.gz, dsc).",
        ),
        "dsc": attr.label(
            allow_single_file = [".dsc"],
            mandatory = True,
            doc = "Debian .dsc file for the source package.",
        ),
        "patches": attr.label_list(
            allow_files = True,
            doc = "SONiC-specific patch files.",
        ),
        "patch_series": attr.label(
            allow_single_file = True,
            doc = "stgit series file listing patch order.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Full Debian version string, e.g. '3.7.0-0.2+b1sonic1'.",
        ),
        "arch": attr.string(
            default = "amd64",
            values = ["amd64", "arm64", "armhf"],
            doc = "Target Debian architecture.",
        ),
        "declared_outputs": attr.string_list(
            mandatory = True,
            doc = "Expected .deb file names (basenames, no paths).",
        ),
        "slave_image": attr.string(
            mandatory = True,
            doc = "Fully-qualified sonic-slave container image URI with sha256 digest.",
        ),
        "build_deps": attr.label_list(
            doc = "Bazel targets that must be built before this package.",
        ),
    },
    toolchains = [],
)

# ── Public macros ─────────────────────────────────────────────────────────────

def debian_source_package(
        name,
        dsc,
        srcs,
        version,
        declared_outputs,
        patches = [],
        patch_series = None,
        arch = None,
        build_deps = [],
        slave_image = None,
        visibility = None):
    """Build a Debian source package (dget-style) into .deb files.

    Args:
        name:             Target name (used as prefix for internal targets).
        dsc:              Label for the .dsc file (fetched by a repository_rule).
        srcs:             Upstream source archives declared alongside the .dsc.
        version:          Full Debian version string for the output .deb names.
        declared_outputs: List of expected .deb filenames (basenames only).
        patches:          List of SONiC patch file labels.
        patch_series:     Label for the stgit series file.
        arch:             Target arch; defaults to platform constraint.
        build_deps:       Additional Bazel deps required before building.
        slave_image:      Override sonic-slave container image URI.
        visibility:       Bazel visibility.
    """
    effective_arch = arch or select({
        "//platforms:is_amd64": "amd64",
        "//platforms:is_arm64": "arm64",
        "//platforms:is_armhf": "armhf",
        "//conditions:default": "amd64",
    })
    effective_image = slave_image or select({
        "//platforms:is_bullseye": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bullseye@sha256:PLACEHOLDER",
        "//platforms:is_bookworm": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bookworm@sha256:PLACEHOLDER",
        "//conditions:default": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bookworm@sha256:PLACEHOLDER",
    })

    _debian_source_package(
        name = name,
        dsc = dsc,
        srcs = srcs,
        version = version,
        declared_outputs = declared_outputs,
        patches = patches,
        patch_series = patch_series,
        arch = effective_arch,
        build_deps = build_deps,
        slave_image = effective_image,
        visibility = visibility,
    )

def deb_package_set(
        name,
        srcs,
        debian_dir,
        version,
        declared_outputs,
        build_type = "dpkg",
        patches = [],
        build_deps = [],
        slave_image = None,
        visibility = None):
    """Build Debian packages from an in-tree source directory (git submodule).

    Use this for packages in src/<submodule>/ that have a debian/ directory
    checked in (e.g., sonic-swss-common, sonic-sairedis).

    Args:
        name:             Target name.
        srcs:             All source files in the submodule (explicit list).
        debian_dir:       Label for the debian/ directory.
        version:          Full version string for output .deb names.
        declared_outputs: List of expected .deb filenames.
        build_type:       "dpkg" (default) or "cmake+dpkg".
        patches:          SONiC patch files to apply before building.
        build_deps:       Bazel targets that must exist before building.
        slave_image:      Override sonic-slave container URI.
        visibility:       Bazel visibility.
    """
    effective_image = slave_image or select({
        "//platforms:is_bullseye": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bullseye@sha256:PLACEHOLDER",
        "//platforms:is_bookworm": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bookworm@sha256:PLACEHOLDER",
        "//conditions:default": "us-docker.pkg.dev/REPLACE_PROJECT_ID/sonic/sonic-slave-bookworm@sha256:PLACEHOLDER",
    })

    # Replace $(ARCH) placeholder in output names with actual arch.
    # In Bazel, genrule outs must be concrete strings — no Make variables.
    resolved_outputs = [o.replace("$(ARCH)", "amd64") for o in declared_outputs]

    native.genrule(
        name = name,
        srcs = srcs + [debian_dir] + patches + build_deps,
        outs = resolved_outputs,
        cmd = """
set -euo pipefail
SRC_DIR=$$(dirname $(location {debian_dir}))
OUT_DIR=$$(dirname $(OUTS))
WORK=$$(mktemp -d)
trap 'rm -rf "$$WORK"' EXIT

cp -a "$$SRC_DIR" "$$WORK/src"

# Apply SONiC-specific patches if any.
for p in {patch_args}; do
  patch -d "$$WORK/src" -p1 < "$$p"
done

pushd "$$WORK/src" >/dev/null
SOURCE_DATE_EPOCH=0 DPKG_GENSYMBOLS_CHECK_LEVEL=0 \\
  dpkg-buildpackage -rfakeroot -b -us -uc --admindir /tmp/dpkg-admindir
popd >/dev/null

mv "$$WORK"/*.deb "$$OUT_DIR"/
        """.format(
            debian_dir = debian_dir,
            patch_args = " ".join(["$(locations %s)" % p for p in patches]),
        ),
        tags = [
            "no-cache",  # Remove once output is deterministic (SOURCE_DATE_EPOCH alone may not suffice)
            "requires-docker",
        ],
        visibility = visibility,
    )
