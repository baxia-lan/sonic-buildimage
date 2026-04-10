#!/usr/bin/env bash
# swss mock_tests runner — builds and runs 6 GTest binaries in Docker.
# Tests: aclorch, portsorch, routeorch, qosorch, bufferorch, copporch, etc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."

echo "=== swss mock_tests ==="

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
find "$REPO_ROOT" -path "*/bazel-bin/*/*.deb" -size +0 2>/dev/null | while read f; do cp "$f" "$STAGING/" 2>/dev/null || true; done
echo "Debs: $(ls "$STAGING"/*.deb 2>/dev/null | wc -l)"

docker run --rm --platform linux/amd64 \
    -v "$STAGING:/debs:ro" \
    -v "$REPO_ROOT/src/sonic-swss:/src:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    debian:bookworm-slim bash -c '
set -euo pipefail
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    redis-server build-essential cmake \
    libgtest-dev libgmock-dev \
    libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libnl-nf-3-dev \
    libhiredis-dev libzmq3-dev libboost-dev libboost-serialization-dev \
    libprotobuf-dev protobuf-compiler pkg-config \
    libyang2-dev nlohmann-json3-dev uuid-dev \
    python3-dev swig autoconf automake libtool \
    libjansson-dev libteam-dev libjemalloc-dev >/dev/null 2>&1

dpkg --force-overwrite --force-depends -i /debs/*.deb 2>&1 || true
apt-get install -f -y -qq 2>/dev/null || true
ldconfig

redis-server --daemonize yes --bind 127.0.0.1

cp -a /src /tmp/swss-test && cd /tmp/swss-test
find . -name .git -type f -delete 2>/dev/null || true
rm -rf .git
git config --global user.email build@sonic && git config --global user.name sonic
git init -q && git add -A . && git commit -qm init 2>/dev/null || true

./autogen.sh 2>&1 | tail -3
./configure --enable-tests 2>&1 | tail -5

echo "=== Building mock_tests ==="
cd tests/mock_tests
make -j$(nproc) 2>&1 | tail -20

FAILED=0
for test_bin in tests tests_intfmgrd tests_teammgrd tests_portsyncd tests_fpmsyncd tests_response_publisher; do
    if [ -f "./$test_bin" ]; then
        echo "=== Running $test_bin ==="
        ./$test_bin --gtest_output=xml:/tmp/${test_bin}-results.xml 2>&1 || FAILED=1
    fi
done

if [ $FAILED -ne 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
fi
echo "=== ALL mock_tests PASSED ==="
'
