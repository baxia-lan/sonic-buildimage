#!/usr/bin/env bash
# Gate 3: sonic-broadcom.bin — hermetic end-to-end build
# Image itself must be hermetic. No size gate.
#
# Maturity: PARTIAL
#   - //platform/broadcom:sonic_broadcom_bin target exists
#   - Kernel BUILD (//src/sonic-linux-kernel) is not checked into this repo.
#     The vmlinuz verification step is blocked until the kernel BUILD file
#     is committed (currently only exists in external fork, downloaded at CI time).
#   - Dependency unit test targets (swss_common_test, sairedis_test) do not yet
#     exist. Blocked until submodule BUILD files are checked in.
set -euo pipefail

echo "=== Gate 3: sonic-broadcom.bin (PARTIAL) ==="

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

# Step 3: Verify kernel — BLOCKED
# //src/sonic-linux-kernel:linux_kernel_debs BUILD.bazel is not checked into
# this repo. It is currently only available from an external fork (baxia-lan)
# and downloaded at CI time. This step is blocked until the BUILD file is
# committed or the submodule gitlink updated to a fork SHA that includes it.
echo "Step 3: Kernel verification — SKIPPED (BUILD not checked in)"
echo "  Blocked: //src/sonic-linux-kernel:linux_kernel_debs"
echo "  Blocked: vmlinuz extraction depends on kernel BUILD"

# Step 4: Dependency unit tests — BLOCKED
# The following labels do not exist in checked-in repo state:
#   //src/sonic-swss-common:swss_common_test
#   //src/sonic-sairedis:sairedis_test
# Blocked until submodule BUILD files are committed.
echo "Step 4: Dependency unit tests — SKIPPED (labels not yet checked in)"
echo "  Blocked: //src/sonic-swss-common:swss_common_test"
echo "  Blocked: //src/sonic-sairedis:sairedis_test"

echo "=== Gate 3: PARTIAL PASS (kernel + dependency tests skipped) ==="
