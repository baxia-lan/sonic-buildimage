#!/usr/bin/env bash
# ONIE image builder — assembles kernel + rootfs + modules into a self-extracting .bin.
# This script is invoked by the onie_image() Bazel rule.
set -euo pipefail

OUTPUT=""
KERNEL=""
ROOTFS=""
PLATFORM=""
MACHINE=""
VERSION=""
MODULES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)  OUTPUT="$2"; shift 2 ;;
        --kernel)  KERNEL="$2"; shift 2 ;;
        --rootfs)  ROOTFS="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --machine) MACHINE="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --module)  MODULES+=("$2"); shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Stage components
cp "$KERNEL" "$WORK/vmlinuz"
cp "$ROOTFS" "$WORK/fs.squashfs"

for mod in "${MODULES[@]}"; do
    cp "$mod" "$WORK/$(basename "$mod")"
done

# Create metadata
cat > "$WORK/machine.conf" <<EOF
onie_machine=$MACHINE
onie_platform=$PLATFORM
sonic_version=$VERSION
EOF

# Create the self-extracting archive
PAYLOAD="$WORK/payload.tar.gz"
SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 \
    --owner=0 --group=0 \
    -czf "$PAYLOAD" -C "$WORK" \
    vmlinuz fs.squashfs machine.conf

# Prepend the installer header
cat installer/install.sh "$PAYLOAD" > "$OUTPUT"
chmod +x "$OUTPUT"

# Size check
SIZE_MB=$(( $(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT") / 1048576 ))
echo "ONIE image: $SIZE_MB MB (platform: $PLATFORM)"
if [ "$SIZE_MB" -gt 400 ]; then
    echo "FAIL: $OUTPUT is $SIZE_MB MB, exceeds 400 MB budget" >&2
    exit 1
fi
