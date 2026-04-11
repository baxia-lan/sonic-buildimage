#!/usr/bin/env bash
# Gate 4: sonic-alpinevs.img.gz — hermetic end-to-end build + tests
# Image itself must be hermetic.
set -euo pipefail

echo "=== Gate 4: sonic-alpinevs.img.gz ==="

# Step 1: Build with hermeticity enforced
echo "Step 1: Building sonic-alpinevs.img.gz..."
bazel build //platform/alpinevs:sonic_alpinevs_img \
  --sandbox_default_allow_network=false \
  --spawn_strategy=sandboxed

# Step 2: Verify output exists and is non-trivial
echo "Step 2: Verifying output..."
IMG="bazel-bin/platform/alpinevs/sonic-alpinevs.img.gz"
[ -f "$IMG" ] || { echo "FAIL: $IMG not found"; exit 1; }
SIZE_MB=$(( $(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG") / 1048576 ))
echo "  sonic-alpinevs.img.gz: ${SIZE_MB} MB"
[ "$SIZE_MB" -gt 10 ] || { echo "FAIL: $SIZE_MB MB is too small"; exit 1; }

# Step 3: Run alpinevs tests
echo "Step 3: Running alpinevs tests..."
bazel test //platform/alpinevs:alpinevs_test \
  --sandbox_default_allow_network=false \
  --test_output=errors || { echo "FAIL: alpinevs tests failed"; exit 1; }

# Step 4: Run dependency unit tests
echo "Step 4: Running dependency tests..."
bazel test //src/sonic-swss-common:swss_common_test \
  //src/sonic-sairedis:sairedis_test \
  --sandbox_default_allow_network=false \
  --test_output=errors || { echo "FAIL: dependency unit tests failed"; exit 1; }

echo "=== Gate 4: PASSED ==="
