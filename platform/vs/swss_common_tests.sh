#!/usr/bin/env bash
# swss-common unit test runner — builds and runs C++ GTest tests in Docker.
# The tests need Redis running and the libswsscommon-dev headers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="debian:bookworm-slim"
CONTAINER="swss-common-tests-$$"

# Find the swss-common debs
DEBS=""
for d in $(find "$SCRIPT_DIR" -name "*.deb" 2>/dev/null) \
         $(find . -path "*/sonic-swss-common/*.deb" -size +0 2>/dev/null); do
    DEBS="$DEBS $d"
done

if [ -z "$DEBS" ]; then
    echo "FAIL: No swss-common debs found. Build first:"
    echo "  bazel build //build/deb/sonic-swss-common:swss_common_debs"
    exit 1
fi

# Stage debs
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"; docker rm -f "$CONTAINER" 2>/dev/null' EXIT
for d in $DEBS; do cp "$d" "$STAGING/" 2>/dev/null || true; done

echo "=== Running swss-common unit tests ==="
echo "Debs: $(ls "$STAGING"/*.deb 2>/dev/null | wc -l)"

docker run --rm --platform linux/amd64 \
    -v "$STAGING:/debs:ro" \
    -v "$SCRIPT_DIR/../../src/sonic-swss-common:/src:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "$IMAGE" \
    bash -c '
set -euo pipefail

# Install test dependencies
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    redis-server build-essential cmake \
    libgtest-dev libgmock-dev \
    libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libnl-nf-3-dev \
    libhiredis-dev libzmq3-dev libboost-dev libboost-serialization-dev \
    libprotobuf-dev protobuf-compiler pkg-config \
    libyang2-dev nlohmann-json3-dev uuid-dev \
    python3-dev swig autoconf automake libtool >/dev/null 2>&1

# Install swss-common debs
dpkg --force-overwrite --force-depends -i /debs/*.deb 2>&1 || true
apt-get install -f -y -qq 2>/dev/null || true
ldconfig

# Start Redis
redis-server --daemonize yes --bind 127.0.0.1

# Build tests from source
cp -a /src /tmp/swss-common-test
cd /tmp/swss-common-test
./autogen.sh 2>&1 | tail -3
./configure --enable-tests 2>&1 | tail -5
make -j$(nproc) tests/tests 2>&1 | tail -10

# Run tests
echo "=== Running GTest ==="
./tests/tests --gtest_output=xml:/tmp/test-results.xml 2>&1
TEST_RC=$?

echo "=== Test Results ==="
if [ $TEST_RC -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "TESTS FAILED (exit code $TEST_RC)"
fi
exit $TEST_RC
'
