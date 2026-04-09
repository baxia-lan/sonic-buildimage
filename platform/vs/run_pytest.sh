#!/usr/bin/env bash
# End-to-end: Build docker-sonic-vs with Bazel, run sonic-swss pytest.
# This is the ULTIMATE verification that the Bazel migration is correct.
#
# Usage:
#   ./platform/vs/run_pytest.sh                    # Quick test (test_port.py)
#   ./platform/vs/run_pytest.sh test_vlan.py       # Specific test
#   ./platform/vs/run_pytest.sh -k test_port_fec   # pytest -k filter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_NAME="docker-sonic-vs:latest"

cd "$REPO_ROOT"

# Step 1: Ensure BUILD.bazel in submodules
echo "=== Step 1: Sync submodule BUILD.bazel files ==="
./demo.sh 2>/dev/null | grep -E '^\s+\+' || true

# Step 2: Build OCI image
echo "=== Step 2: Building docker-sonic-vs OCI image ==="
bazel build //platform/vs:docker_sonic_vs_tarball \
  --spawn_strategy=local --strategy=CopyToDirectory=local --jobs=1

# Step 3: Load into Docker
echo "=== Step 3: Loading into Docker ==="
bazel-bin/platform/vs/docker_sonic_vs_tarball.sh

# Step 4: Tag for pytest
echo "=== Step 4: Tagging image ==="
docker tag sonic/docker_sonic_vs:latest "$IMAGE_NAME"
echo "  Tagged as $IMAGE_NAME"

# Step 5: Quick smoke test
echo "=== Step 5: Smoke test ==="
docker run --rm --entrypoint bash "$IMAGE_NAME" -c '
  for bin in syncd orchagent redis-server supervisord sonic-db-cli; do
    which $bin 2>/dev/null && echo "  $bin: OK" || echo "  $bin: MISSING"
  done
  python3 -c "import swsscommon; print(\"  swsscommon: OK\")" 2>/dev/null || echo "  swsscommon: MISSING"
'

# Step 6: Run pytest
echo "=== Step 6: Running sonic-swss pytest ==="
cd "$REPO_ROOT/src/sonic-swss/tests"

if [ $# -gt 0 ]; then
  sudo pytest --imgname="$IMAGE_NAME" -v "$@"
else
  echo "Running test_port.py (quick test)..."
  sudo pytest --imgname="$IMAGE_NAME" -v test_port.py
fi
