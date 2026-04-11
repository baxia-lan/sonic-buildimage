#!/usr/bin/env bash
# Gate 3: sonic-broadcom.bin — hermetic end-to-end build
# Image itself must be hermetic. No size gate.
set -euo pipefail

echo "=== Gate 3: sonic-broadcom.bin ==="

# Step 1: Build with hermeticity enforced
echo "Step 1: Building sonic-broadcom.bin..."
bazel build //platform/broadcom:sonic_broadcom_bin \
  --sandbox_default_allow_network=false \
  --spawn_strategy=sandboxed

# Step 2: Verify output exists and is non-trivial
echo "Step 2: Verifying output..."
BIN="bazel-bin/platform/broadcom/sonic_broadcom_bin.bin"
[ -f "$BIN" ] || { echo "FAIL: $BIN not found"; exit 1; }
SIZE_MB=$(( $(stat -c%s "$BIN" 2>/dev/null || stat -f%z "$BIN") / 1048576 ))
echo "  sonic-broadcom.bin: ${SIZE_MB} MB"
[ "$SIZE_MB" -gt 10 ] || { echo "FAIL: $SIZE_MB MB is too small — likely stub, not real image"; exit 1; }

# Step 3: Verify kernel is real (not stub)
echo "Step 3: Verifying kernel..."
VMLINUZ="bazel-bin/src/sonic-linux-kernel/vmlinuz-extracted"
[ -f "$VMLINUZ" ] || { echo "FAIL: vmlinuz not found"; exit 1; }
KSIZE=$(( $(stat -c%s "$VMLINUZ" 2>/dev/null || stat -f%z "$VMLINUZ") / 1048576 ))
echo "  vmlinuz: ${KSIZE} MB"
[ "$KSIZE" -gt 5 ] || { echo "FAIL: vmlinuz ${KSIZE} MB — too small, likely stub"; exit 1; }

# Step 4: Run dependency unit tests
echo "Step 4: Running dependency tests..."
bazel test //src/sonic-swss-common:swss_common_test \
  //src/sonic-sairedis:sairedis_test \
  --sandbox_default_allow_network=false \
  --test_output=errors || { echo "FAIL: dependency unit tests failed"; exit 1; }

echo "=== Gate 3: PASSED ==="
