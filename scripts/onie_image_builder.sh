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

# Stage components
cp "$KERNEL" "$WORK/vmlinuz"
cp "$ROOTFS" "$WORK/fs.rootfs"

if [ ${#MODULES[@]} -gt 0 ]; then
    for mod in "${MODULES[@]}"; do
        cp "$mod" "$WORK/$(basename "$mod")"
    done
fi

# Create metadata
cat > "$WORK/machine.conf" <<EOF
onie_machine=$MACHINE
onie_platform=$PLATFORM
sonic_version=$VERSION
EOF

# Build list of payload files
PAYLOAD_FILES="vmlinuz fs.rootfs machine.conf"
for mod in "${MODULES[@]}"; do
    PAYLOAD_FILES="$PAYLOAD_FILES $(basename "$mod")"
done

# Create the self-extracting archive
PAYLOAD="$WORK/payload.tar.gz"
if tar --sort=name -cf /dev/null --files-from /dev/null 2>/dev/null; then
    SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 --owner=0 --group=0 \
        -czf "$PAYLOAD" -C "$WORK" $PAYLOAD_FILES
else
    SOURCE_DATE_EPOCH=0 tar -czf "$PAYLOAD" -C "$WORK" $PAYLOAD_FILES
fi

# Prepend the installer header
cat "$INSTALLER_SCRIPT" "$PAYLOAD" > "$OUTPUT"
chmod +x "$OUTPUT"

# Size check
SIZE_MB=$(( $(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT") / 1048576 ))
echo "ONIE image: $SIZE_MB MB (platform: $PLATFORM)"
if [ "$SIZE_MB" -gt 400 ]; then
    echo "FAIL: $OUTPUT is $SIZE_MB MB, exceeds 400 MB budget" >&2
    exit 1
fi
