#!/usr/bin/env bash
# Smoke test for docker-sonic-vs built by Bazel.
# Verifies the image boots, services start, and basic DB operations work.
set -euo pipefail

IMAGE="docker-sonic-vs:bazel"
CONTAINER="vs-smoke-test-$$"
TIMEOUT=120

echo "=== Loading docker-sonic-vs ==="
TARBALL="$(dirname "$0")/docker-sonic-vs.tar.gz"
if [ -f "$TARBALL" ]; then
  docker load -i "$TARBALL"
fi

echo "=== Starting container ==="
docker run -d --name "$CONTAINER" --privileged "$IMAGE"

cleanup() {
  echo "=== Cleanup ==="
  docker logs "$CONTAINER" 2>&1 | tail -30
  docker rm -f "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Waiting for services (${TIMEOUT}s timeout) ==="
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  # Check if start.sh has exited (meaning all services are started)
  STATUS=$(docker exec "$CONTAINER" supervisorctl status start.sh 2>/dev/null | awk '{print $2}' || echo "UNKNOWN")
  if [ "$STATUS" = "EXITED" ]; then
    echo "start.sh completed after ${ELAPSED}s"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  ${ELAPSED}s: start.sh status=$STATUS"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "FAIL: start.sh did not complete within ${TIMEOUT}s"
  docker exec "$CONTAINER" supervisorctl status 2>/dev/null || true
  exit 1
fi

echo "=== Service status ==="
docker exec "$CONTAINER" supervisorctl status

echo "=== Checking critical services ==="
FAILED=0
for svc in redis-server syncd orchagent; do
  STATUS=$(docker exec "$CONTAINER" supervisorctl status "$svc" 2>/dev/null | awk '{print $2}' || echo "MISSING")
  if [ "$STATUS" = "RUNNING" ]; then
    echo "  $svc: RUNNING"
  else
    echo "  $svc: $STATUS (EXPECTED RUNNING)"
    FAILED=1
  fi
done

echo "=== Testing Redis connectivity ==="
docker exec "$CONTAINER" redis-cli ping | grep -q PONG && echo "  redis: PONG" || { echo "  redis: FAIL"; FAILED=1; }

echo "=== Testing sonic-db-cli ==="
docker exec "$CONTAINER" sonic-db-cli CONFIG_DB keys '*' 2>/dev/null | head -5 && echo "  sonic-db-cli: OK" || echo "  sonic-db-cli: WARN"

echo "=== Testing swsscommon Python ==="
docker exec "$CONTAINER" python3 -c "import swsscommon; print('swsscommon OK')" 2>/dev/null && echo "  swsscommon: OK" || echo "  swsscommon: WARN"

if [ $FAILED -ne 0 ]; then
  echo "FAIL: Some critical services are not running"
  exit 1
fi

echo "=== PASS: docker-sonic-vs smoke test ==="
