#!/usr/bin/env bash
# VS pytest runner — runs sonic-swss test_port.py against Bazel-built docker-sonic-vs.
# This is the ultimate verification that the Bazel build is correct.
#
# Usage:
#   bazel test //platform/vs:pytest_vs --test_output=all
#   (or run directly: ./platform/vs/pytest_vs.sh)
set -euo pipefail

IMAGE="docker-sonic-vs:latest"
CONTAINER="vs-pytest-$$"
TIMEOUT=120

# ── Load image if tarball available ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL="$SCRIPT_DIR/docker_sonic_vs_tarball.sh"
if [ -f "$TARBALL" ]; then
    echo "=== Loading docker-sonic-vs from tarball ==="
    bash "$TARBALL" 2>/dev/null || true
    docker tag sonic/docker_sonic_vs:latest "$IMAGE" 2>/dev/null || true
fi

# ── Verify image exists ─────────────────────────────────────────────────────
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "FAIL: $IMAGE not found. Build it first:"
    echo "  bazel build //platform/vs:docker_sonic_vs_tarball"
    exit 1
fi

# ── Start container ──────────────────────────────────────────────────────────
echo "=== Starting container ==="
CONTAINER_ID=$(docker run -d --privileged "$IMAGE")
trap 'docker rm -f "$CONTAINER_ID" 2>/dev/null' EXIT

# ── Wait for Redis ───────────────────────────────────────────────────────────
echo "=== Waiting for Redis (${TIMEOUT}s timeout) ==="
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec "$CONTAINER_ID" redis-cli ping 2>/dev/null | grep -q PONG; then
        echo "Redis up after ${ELAPSED}s"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "FAIL: Redis not responsive after ${TIMEOUT}s"
    docker logs "$CONTAINER_ID" 2>&1 | tail -30
    exit 1
fi

# ── Wait for orchagent ───────────────────────────────────────────────────────
echo "=== Waiting for orchagent ==="
for i in $(seq 1 12); do
    STATUS=$(docker exec "$CONTAINER_ID" supervisorctl status orchagent 2>/dev/null | awk '{print $2}' || echo "UNKNOWN")
    if [ "$STATUS" = "RUNNING" ]; then
        echo "orchagent RUNNING after $((i*5))s"
        break
    fi
    sleep 5
done

# ── Run pytest ───────────────────────────────────────────────────────────────
echo "=== Running test_port.py ==="
cd "$SCRIPT_DIR/../../src/sonic-swss/tests"

# Install test dependencies if needed
pip3 install pytest docker redis 2>/dev/null || true

python3 -m pytest \
    --imgname="$IMAGE" \
    -v \
    test_port.py \
    -x \
    --timeout=300 \
    2>&1

echo "=== ALL TESTS PASSED ==="
