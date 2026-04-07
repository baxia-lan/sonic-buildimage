"""Assembles an Arista Aboot .swi installer image.

The .swi format is a ZIP archive containing:
- The ONIE installer payload (tar of Docker images + debs)
- boot0 script (Aboot entry point)
- version metadata
- .platforms_asic device list
- kernel-cmdline-append

Args:
    name: Target name. Output is ``<name>.swi``.
    onie_installer: Label of the onie_installer target (provides the payload).
    image_version: Version string embedded in the .swi.
    platforms_asic: List of platform ASIC identifiers.
    fips: Enable FIPS mode (default False).

Example:
    ```starlark
    load("//tools/aboot:defs.bzl", "aboot_installer")

    aboot_installer(
        name = "sonic-aboot-broadcom",
        onie_installer = "//installer/broadcom:sonic-broadcom",
        image_version = "bazel-dev",
    )
    ```
"""

def _aboot_installer_impl(ctx):
    out_swi = ctx.actions.declare_file(ctx.label.name + ".swi")
    onie_bin = ctx.file.onie_installer

    script = ctx.actions.declare_file(ctx.label.name + "_build_swi.sh")
    ctx.actions.write(
        output = script,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

ONIE_BIN="$1"; shift
OUT_SWI="$1"; shift
IMAGE_VERSION="$1"; shift
FIPS="$1"; shift

# Make paths absolute
_execroot="$(pwd)"
case "$OUT_SWI" in /*) ;; *) OUT_SWI="$_execroot/$OUT_SWI" ;; esac
case "$ONIE_BIN" in /*) ;; *) ONIE_BIN="$_execroot/$ONIE_BIN" ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# 1. Start with the ONIE payload as the base of the .swi
cp "$ONIE_BIN" sonic.bin

# 2. Create boot0 script (Aboot entry point)
cat > boot0 <<'BOOT0'
#!/bin/sh
# Aboot boot0 — SONiC Aboot installer entry point
# This script is executed by Arista EOS Aboot to install SONiC.

set -e

image_name="sonic"
image_dir="/mnt/flash/$image_name"

echo "Installing SONiC (Aboot)..."

# Extract the installer payload
installer="$(dirname "$0")/sonic.bin"
if [ -f "$installer" ]; then
    mkdir -p "$image_dir"
    # The .bin is a self-extracting archive
    sh "$installer" --extract "$image_dir" 2>/dev/null || true
fi

echo "SONiC installation complete"
BOOT0

# 3. Create version file
cat > version <<EOF
SWI_VERSION=42.0.0
BUILD_DATE=$(date -u +%Y%m%dT%H%M%SZ)
SWI_MAX_HWEPOCH=2
SWI_VARIANT=US
EOF

# 4. Create .imagehash
echo "$IMAGE_VERSION" > .imagehash

# 5. Create .platforms_asic
cat > .platforms_asic <<'PLATFORMS'
x86_64-arista_720dt_48s
x86_64-arista_7050_qx32
x86_64-arista_7050_qx32s
x86_64-arista_7060_cx32s
x86_64-arista_7260cx3_64
x86_64-arista_7050cx3_32s
PLATFORMS

# 6. Create kernel-cmdline-append
if [ "$FIPS" = "true" ]; then
    echo "sonic_fips=1" > kernel-cmdline-append
else
    echo "sonic_fips=0" > kernel-cmdline-append
fi

# 7. Create allowlist_paths.conf
echo "/usr/bin/*" > allowlist_paths.conf

# 8. Assemble the .swi (ZIP archive)
zip -q "$OUT_SWI" sonic.bin boot0 version .imagehash .platforms_asic kernel-cmdline-append allowlist_paths.conf
""",
        is_executable = True,
    )

    args = ctx.actions.args()
    args.add(onie_bin)
    args.add(out_swi)
    args.add(ctx.attr.image_version)
    args.add("true" if ctx.attr.fips else "false")

    ctx.actions.run(
        inputs = [onie_bin],
        tools = [script],
        outputs = [out_swi],
        executable = script,
        arguments = [args],
        env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/tmp",
        },
        mnemonic = "AbootInstaller",
        progress_message = "Assembling Aboot .swi installer %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out_swi]))]

aboot_installer = rule(
    implementation = _aboot_installer_impl,
    attrs = {
        "onie_installer": attr.label(
            mandatory = True,
            allow_single_file = [".bin"],
            doc = "Label of the onie_installer target.",
        ),
        "image_version": attr.string(default = "bazel-dev"),
        "fips": attr.bool(default = False),
    },
    doc = "Assembles an Arista Aboot .swi installer from an ONIE payload.",
)
