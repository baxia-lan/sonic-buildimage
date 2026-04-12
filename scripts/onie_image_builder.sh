#!/usr/bin/env bash
# ONIE image builder — assembles kernel + rootfs + modules into a self-extracting .bin.
# This script is invoked by the onie_image() Bazel rule.
#
# Output format (sharch — shell archive):
#   [sharch_body.sh header with sha1/size filled in]
#   exit_marker
#   [tar payload containing:
#     installer/install.sh
#     dockerfs.tar.gz (Docker service images)
#     platform.tar.gz (platform config + kernel modules)
#     boot0 (kernel vmlinuz)]
set -euo pipefail

OUTPUT=""
KERNEL=""
ROOTFS=""
PLATFORM=""
MACHINE=""
VERSION=""
INSTALLER_SCRIPT=""
MODULES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)    OUTPUT="$2"; shift 2 ;;
        --kernel)    KERNEL="$2"; shift 2 ;;
        --rootfs)    ROOTFS="$2"; shift 2 ;;
        --platform)  PLATFORM="$2"; shift 2 ;;
        --machine)   MACHINE="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --installer) INSTALLER_SCRIPT="$2"; shift 2 ;;
        --module)    MODULES+=("$2"); shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

[ -z "$OUTPUT" ] && { echo "ERROR: --output required" >&2; exit 1; }
[ -z "$KERNEL" ] && { echo "ERROR: --kernel required" >&2; exit 1; }
[ -z "$ROOTFS" ] && { echo "ERROR: --rootfs required" >&2; exit 1; }
[ -z "$INSTALLER_SCRIPT" ] && { echo "ERROR: --installer required" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Find the sharch_body.sh template (sibling of install.sh)
INSTALLER_DIR=$(dirname "$INSTALLER_SCRIPT")
SHARCH_BODY="$INSTALLER_DIR/sharch_body.sh"
[ -f "$SHARCH_BODY" ] || { echo "ERROR: sharch_body.sh not found at $SHARCH_BODY" >&2; exit 1; }

# ── Build the tar payload ──────────────────────────────────────────────────
PAYLOAD_DIR="$WORK/payload"
mkdir -p "$PAYLOAD_DIR/installer"

# Installer script
cp "$INSTALLER_SCRIPT" "$PAYLOAD_DIR/installer/install.sh"
chmod +x "$PAYLOAD_DIR/installer/install.sh"

# Docker filesystem (service container images)
cp "$ROOTFS" "$PAYLOAD_DIR/dockerfs.tar.gz"

# Kernel
cp "$KERNEL" "$PAYLOAD_DIR/boot0"

# Platform config
mkdir -p "$WORK/platform_staging"
cat > "$WORK/platform_staging/machine.conf" <<EOF
onie_machine=$MACHINE
onie_platform=$PLATFORM
sonic_version=$VERSION
EOF
if [ ${#MODULES[@]} -gt 0 ]; then
    for mod in "${MODULES[@]}"; do
        cp "$mod" "$WORK/platform_staging/$(basename "$mod")"
    done
fi
TAR_FLAGS=""
if tar --sort=name -cf /dev/null --files-from /dev/null 2>/dev/null; then
    TAR_FLAGS="--sort=name --mtime=@0 --owner=0 --group=0"
fi
SOURCE_DATE_EPOCH=0 tar $TAR_FLAGS -czf "$PAYLOAD_DIR/platform.tar.gz" \
    -C "$WORK/platform_staging" .

# Create payload tar
PAYLOAD_TAR="$WORK/payload.tar"
SOURCE_DATE_EPOCH=0 tar $TAR_FLAGS -cf "$PAYLOAD_TAR" -C "$PAYLOAD_DIR" .

# ── Build the sharch (self-extracting archive) ──────────────────────────────
PAYLOAD_SIZE=$(stat -f%z "$PAYLOAD_TAR" 2>/dev/null || stat -c%s "$PAYLOAD_TAR")
PAYLOAD_SHA1=$(sha1sum "$PAYLOAD_TAR" | awk '{print $1}')

# Replace template variables in sharch_body.sh
sed -e "s/%%PAYLOAD_IMAGE_SIZE%%/$PAYLOAD_SIZE/" \
    -e "s/%%IMAGE_SHA1%%/$PAYLOAD_SHA1/" \
    "$SHARCH_BODY" > "$WORK/sharch_header.sh"

# Concatenate: header + payload
cat "$WORK/sharch_header.sh" "$PAYLOAD_TAR" > "$OUTPUT"
chmod +x "$OUTPUT"

# ── Size check ─────────────────────────────────────────────────────────────
SIZE_MB=$(( $(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT") / 1048576 ))
echo "ONIE image: $SIZE_MB MB (platform: $PLATFORM)"
DOCKERFS_SIZE=$(( $(stat -f%z "$PAYLOAD_DIR/dockerfs.tar.gz" 2>/dev/null || stat -c%s "$PAYLOAD_DIR/dockerfs.tar.gz") / 1048576 ))
KERNEL_SIZE=$(( $(stat -f%z "$PAYLOAD_DIR/boot0" 2>/dev/null || stat -c%s "$PAYLOAD_DIR/boot0") / 1048576 ))
echo "  dockerfs: $DOCKERFS_SIZE MB | kernel: $KERNEL_SIZE MB | sha1: $PAYLOAD_SHA1"
if [ "$SIZE_MB" -gt 700 ]; then
    echo "FAIL: $OUTPUT is $SIZE_MB MB, exceeds 700 MB budget" >&2
    exit 1
fi
