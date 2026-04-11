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
bash bazel-bin/platform/vs/docker_sonic_vs_tarball.sh
docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest

# Step 3: Verify debs exist
echo "Step 3: Verifying swss-common debs..."
ls -lh bazel-bin/src/sonic-swss-common/*.deb

# Step 4: Run pytest inside bookworm container
# The swss-common debs link against bookworm libs. Running pytest on a
# non-bookworm host (Ubuntu 24.04, etc.) fails due to library mismatches.
# Solution: run pytest in a bookworm container with full host access.
echo "Step 4: Running pytest inside bookworm container..."
DEBS_DIR=$(realpath bazel-bin/src/sonic-swss-common)
TESTS_DIR=$(realpath src/sonic-swss/tests)
mkdir -p /var/run/redis-vs

docker run --rm --privileged \
  --pid=host \
  --network=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/run/redis-vs:/var/run/redis-vs \
  -v /var/run/netns:/var/run/netns \
  -v "${DEBS_DIR}:/debs:ro" \
  -v "${TESTS_DIR}:/tests" \
  -e DEBIAN_FRONTEND=noninteractive \
  debian:bookworm-slim bash -c '
    set -euo pipefail

    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-dev \
      docker.io iproute2 util-linux \
      libhiredis0.14 libzmq5 \
      libnl-3-200 libnl-genl-3-200 libnl-route-3-200 libnl-nf-3-200 \
      libboost-serialization1.74.0 libyang2 libprotobuf32 \
      libssl3 libjemalloc2 libjansson4 uuid-runtime

    dpkg --force-overwrite --force-depends -i \
      /debs/libswsscommon_1.0.0_amd64.deb \
      /debs/python3-swsscommon_1.0.0_amd64.deb
    ldconfig

    python3 -c "from swsscommon import swsscommon; print(\"swsscommon: OK\")"

    pip3 install --break-system-packages pytest pytest-timeout docker redis

    cd /tests
    pytest --imgname=docker-sonic-vs:latest -v --timeout=600
  '

echo "=== Gate 1: PASSED ==="
