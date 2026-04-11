#!/usr/bin/env bash
# ONIE image builder — assembles kernel + rootfs + modules into a self-extracting .bin.
# This script is invoked by the onie_image() Bazel rule.
#
# The output matches the format expected by installer/install.sh:
#   1. Shell script header (install.sh)
#   2. ZIP payload (fs.zip) containing:
#      - dockerfs.tar.gz (Docker images as tarballs)
#      - platform.tar.gz (platform config)
#      - boot0 (kernel vmlinuz)
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

# ── Stage 1: dockerfs.tar.gz (service container images) ────────────────────
# The rootfs tar.gz from sonic_rootfs_image contains Docker tarballs.
# Rename it to dockerfs.tar.gz for the ONIE payload.
cp "$ROOTFS" "$WORK/dockerfs.tar.gz"

# ── Stage 2: platform.tar.gz (platform-specific files) ────────────────────
mkdir -p "$WORK/platform"
cat > "$WORK/platform/machine.conf" <<EOF
onie_machine=$MACHINE
onie_platform=$PLATFORM
sonic_version=$VERSION
EOF

# Add kernel modules if provided
if [ ${#MODULES[@]} -gt 0 ]; then
    mkdir -p "$WORK/platform/modules"
    for mod in "${MODULES[@]}"; do
        cp "$mod" "$WORK/platform/modules/$(basename "$mod")"
    done
fi

# Create platform.tar.gz
PLATFORM_TAR="$WORK/platform.tar.gz"
if tar --sort=name -cf /dev/null --files-from /dev/null 2>/dev/null; then
    SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 --owner=0 --group=0 \
        -czf "$PLATFORM_TAR" -C "$WORK/platform" .
else
    tar -czf "$PLATFORM_TAR" -C "$WORK/platform" .
fi

# ── Stage 3: Kernel boot image ─────────────────────────────────────────────
cp "$KERNEL" "$WORK/boot0"

# ── Stage 4: Create ONIE ZIP payload (fs.zip) ─────────────────────────────
# The installer/install.sh extracts this ZIP.
PAYLOAD="$WORK/fs.zip"
if command -v zip >/dev/null 2>&1; then
    (cd "$WORK" && zip -q "$PAYLOAD" dockerfs.tar.gz platform.tar.gz boot0)
else
    # Fallback: create tar.gz if zip not available (non-standard but functional)
    if tar --sort=name -cf /dev/null --files-from /dev/null 2>/dev/null; then
        SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 --owner=0 --group=0 \
            -czf "$PAYLOAD" -C "$WORK" dockerfs.tar.gz platform.tar.gz boot0
    else
        tar -czf "$PAYLOAD" -C "$WORK" dockerfs.tar.gz platform.tar.gz boot0
    fi
fi

# ── Stage 5: Create self-extracting installer ──────────────────────────────
# Prepend the installer shell script header to the payload.
# The installer script uses `sed -e '1,/^exit_marker$/d'` to find the payload.
cat "$INSTALLER_SCRIPT" "$PAYLOAD" > "$OUTPUT"
chmod +x "$OUTPUT"

# ── Stage 6: Size check ───────────────────────────────────────────────────
SIZE_MB=$(( $(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT") / 1048576 ))
echo "ONIE image: $SIZE_MB MB (platform: $PLATFORM)"
echo "  dockerfs: $(( $(stat -f%z "$WORK/dockerfs.tar.gz" 2>/dev/null || stat -c%s "$WORK/dockerfs.tar.gz") / 1048576 )) MB"
echo "  platform: $(( $(stat -f%z "$PLATFORM_TAR" 2>/dev/null || stat -c%s "$PLATFORM_TAR") / 1048576 )) MB"
echo "  kernel:   $(( $(stat -f%z "$WORK/boot0" 2>/dev/null || stat -c%s "$WORK/boot0") / 1048576 )) MB"
if [ "$SIZE_MB" -gt 400 ]; then
    echo "FAIL: $OUTPUT is $SIZE_MB MB, exceeds 400 MB budget" >&2
    exit 1
fi
