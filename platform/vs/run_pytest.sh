#!/usr/bin/env bash
# Run sonic-swss pytest against Bazel-built docker-sonic-vs.
# This is the ULTIMATE verification that the Bazel build is correct.
#
# Usage:
#   ./platform/vs/run_pytest.sh [test_file] [extra_pytest_args...]
#
# Examples:
#   ./platform/vs/run_pytest.sh                        # Run all tests
#   ./platform/vs/run_pytest.sh test_port.py           # Run port tests only
#   ./platform/vs/run_pytest.sh test_port.py -k test_port_fec  # Run specific test
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_NAME="docker-sonic-vs:latest"
TARBALL="$REPO_ROOT/bazel-bin/platform/vs/docker-sonic-vs.tar.gz"

# Step 1: Build if needed
if [ ! -f "$TARBALL" ]; then
  echo "=== Building docker-sonic-vs ==="
  cd "$REPO_ROOT"
  bazel build //platform/vs:docker_sonic_vs \
    --spawn_strategy=local --strategy=CopyToDirectory=local --jobs=1
fi

# Step 2: Load into Docker
echo "=== Loading docker-sonic-vs ==="
docker load -i "$TARBALL"
# Tag with the name pytest expects
LOADED_IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep docker-sonic-vs | head -1)
docker tag "$LOADED_IMAGE" "$IMAGE_NAME"
echo "Tagged as $IMAGE_NAME"

# Step 3: Run pytest
echo "=== Running sonic-swss pytest ==="
cd "$REPO_ROOT/src/sonic-swss/tests"

TEST_FILE="${1:-}"
shift 2>/dev/null || true

if [ -n "$TEST_FILE" ]; then
  sudo pytest --imgname="$IMAGE_NAME" -v "$TEST_FILE" "$@"
else
  # Run a focused subset of tests that cover core functionality
  echo "Running core test suite (port, VLAN, interface, neighbor)..."
  sudo pytest --imgname="$IMAGE_NAME" -v \
    test_port.py \
    test_vlan.py \
    test_interface.py \
    test_neighbor.py \
    "$@" 2>&1 || {
      echo ""
      echo "=== Some tests failed. This is expected for first-time Bazel builds ==="
      echo "Check which services are missing and fix the docker-sonic-vs BUILD.bazel"
      exit 1
    }
fi

echo "=== pytest PASSED ==="
