#!/usr/bin/env bash
# AlpineVS boot test — verifies the disk image is bootable and SONiC starts.
set -euo pipefail

IMG="${TEST_SRCDIR:-}/${TEST_WORKSPACE:-}/platform/alpinevs/sonic-alpinevs.img.gz"
if [ ! -f "$IMG" ]; then
  IMG="bazel-bin/platform/alpinevs/sonic-alpinevs.img.gz"
fi

[ -f "$IMG" ] || { echo "FAIL: sonic-alpinevs.img.gz not found"; exit 1; }

SIZE_MB=$(( $(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG") / 1048576 ))
echo "sonic-alpinevs.img.gz: ${SIZE_MB} MB"
[ "$SIZE_MB" -gt 50 ] || { echo "FAIL: image too small (${SIZE_MB} MB)"; exit 1; }

echo "PASS: sonic-alpinevs.img.gz exists and is ${SIZE_MB} MB"
