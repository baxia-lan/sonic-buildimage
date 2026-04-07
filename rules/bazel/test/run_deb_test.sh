#!/usr/bin/env bash
# Run tests for a Debian source package inside Docker.
# Usage: run_deb_test.sh <src_dir> <test_cmd>
set -euo pipefail

SRC_DIR="$1"
TEST_CMD="${2:-make check}"

# Common build deps (same as deb_package_set)
COMMON_DEPS="build-essential dpkg-dev cmake libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libnl-nf-3-dev libhiredis-dev swig libgtest-dev libgmock-dev libboost-dev libboost-serialization-dev libzmq3-dev pkg-config nlohmann-json3-dev python3-dev libprotobuf-dev protobuf-compiler autoconf automake libtool libyang2-dev uuid-dev libclang-dev clang autoconf-archive libjansson-dev libteam-dev libjemalloc-dev ca-certificates curl"

docker run --rm --platform linux/amd64 \
  -v "$(cd "$SRC_DIR" && pwd):/src:ro" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e SOURCE_DATE_EPOCH=0 \
  debian:bookworm-slim \
  bash -euo pipefail -c "
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends $COMMON_DEPS
    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq.hpp -o /usr/include/zmq.hpp
    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq_addon.hpp -o /usr/include/zmq_addon.hpp
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal 2>/dev/null
    export PATH=/root/.cargo/bin:\$PATH
    cp -a /src /tmp/build-src && cd /tmp/build-src
    find . -name .git -type f -delete 2>/dev/null || true
    rm -rf .git
    git config --global user.email build@sonic && git config --global user.name sonic
    git init -q && git add -A . && git commit -qm init 2>/dev/null || true
    # Configure and build
    if [ -f autogen.sh ]; then ./autogen.sh; fi
    if [ -f configure ]; then ./configure --disable-yangmodules --disable-python2 2>&1 | tail -5; fi
    make -j2 2>&1 | tail -10
    # Run tests
    echo '=== Running tests ==='
    $TEST_CMD 2>&1
    echo '=== Tests passed ==='
  "
