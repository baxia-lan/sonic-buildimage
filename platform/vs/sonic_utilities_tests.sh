#!/usr/bin/env bash
# sonic-utilities pytest runner — runs 636+ test files in Docker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."

echo "=== sonic-utilities tests ==="

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
find "$REPO_ROOT" -path "*/bazel-bin/*/*.deb" -size +0 2>/dev/null | while read f; do cp "$f" "$STAGING/" 2>/dev/null || true; done

docker run --rm --platform linux/amd64 \
    -v "$STAGING:/debs:ro" \
    -v "$REPO_ROOT/src/sonic-utilities:/src:ro" \
    -v "$REPO_ROOT/src/sonic-py-common:/sonic-py-common:ro" \
    -v "$REPO_ROOT/src/sonic-config-engine:/sonic-config-engine:ro" \
    -v "$REPO_ROOT/src/sonic-yang-models:/sonic-yang-models:ro" \
    -v "$REPO_ROOT/src/sonic-yang-mgmt:/sonic-yang-mgmt:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    debian:bookworm-slim bash -c '
set -euo pipefail
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    python3 python3-pip python3-dev python3-setuptools \
    redis-server build-essential \
    libhiredis-dev libnl-3-dev libnl-genl-3-dev libzmq3-dev \
    libyang2-dev >/dev/null 2>&1

dpkg --force-overwrite --force-depends -i /debs/*.deb 2>&1 || true
apt-get install -f -y -qq 2>/dev/null || true
ldconfig

redis-server --daemonize yes --bind 127.0.0.1

# Install SONiC Python dependencies
pip3 install --break-system-packages \
    jinja2 netaddr natsort click tabulate xmltodict \
    jsonpatch jsonpointer pyyaml pyangbind bitarray \
    sonic-py-common sonic-config-engine sonic-yang-models sonic-yang-mgmt \
    2>/dev/null || true

# Install sonic-utilities in test mode
cd /tmp && cp -a /src sonic-utilities && cd sonic-utilities
pip3 install --break-system-packages ".[testing]" 2>/dev/null || \
    pip3 install --break-system-packages -e . 2>/dev/null || true

echo "=== Running sonic-utilities pytest ==="
python3 -m pytest tests/ -x --timeout=120 -q 2>&1 | tail -30
echo "=== sonic-utilities tests DONE ==="
'
