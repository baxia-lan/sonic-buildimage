#!/usr/bin/env bash
# Gate 1: docker-sonic-vs.gz — build, load, boot, pytest
# This test FAILS if any step fails. No continue-on-error.
set -euo pipefail

echo "=== Gate 1: docker-sonic-vs.gz ==="

# Step 1: Build with hermeticity enforced
echo "Step 1: Building docker-sonic-vs..."
bazel build //platform/vs:docker_sonic_vs_tarball \
  --sandbox_default_allow_network=false \
  --spawn_strategy=sandboxed

# Step 2: Load image
echo "Step 2: Loading image..."
bazel-bin/platform/vs/docker_sonic_vs_tarball.sh

# Step 3: Tag
docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest

# Step 4: Boot and verify services
echo "Step 3: Booting container..."
CONTAINER=$(docker run -d --privileged docker-sonic-vs:latest)
trap "docker rm -f $CONTAINER 2>/dev/null" EXIT

echo "Step 4: Waiting for services (300s timeout)..."
for i in $(seq 1 60); do
  if docker exec "$CONTAINER" redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "  Redis up after $((i * 5))s"
    break
  fi
  [ "$i" -eq 60 ] && { echo "FAIL: Redis not responding after 300s"; docker logs "$CONTAINER" | tail -30; exit 1; }
  sleep 5
done

# Step 5: Verify critical services
echo "Step 5: Verifying services..."
for svc in redis-server syncd orchagent; do
  STATUS=$(docker exec "$CONTAINER" supervisorctl status "$svc" 2>/dev/null | awk '{print $2}')
  [ "$STATUS" = "RUNNING" ] || { echo "FAIL: $svc is $STATUS, expected RUNNING"; exit 1; }
  echo "  $svc: RUNNING"
done

# Step 6: Run full pytest
echo "Step 6: Running sonic-swss pytest..."
cd src/sonic-swss/tests
sudo pytest --imgname=docker-sonic-vs:latest -v --timeout=600

echo "=== Gate 1: PASSED ==="
