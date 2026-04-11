#!/usr/bin/env bash
# Assert that docker-sonic-vs image contains all required binaries and libraries.
# This runs as a Bazel test target — no Docker needed, just tar inspection.
set -euo pipefail

IMAGE_TAR="${1:?Usage: $0 <image-tarball>}"
ERRORS=0

assert_contains() {
    local pattern="$1"
    local description="$2"
    if tar tf "$IMAGE_TAR" | grep -q "$pattern"; then
        echo "  OK: $description ($pattern)"
    else
        echo "  FAIL: $description — $pattern not found"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Verifying docker-sonic-vs image contents ==="

# Entrypoint chain
assert_contains "usr/local/bin/supervisord" "supervisord entrypoint"
assert_contains "usr/bin/python3" "python3 binary"
assert_contains "usr/local/lib/python3.11/dist-packages/supervisor/" "supervisor module"

# Key SONiC binaries (from swss deb)
assert_contains "usr/bin/orchagent" "orchagent"
assert_contains "usr/bin/neighsyncd" "neighsyncd"
assert_contains "usr/bin/portsyncd" "portsyncd"
assert_contains "usr/bin/vlanmgrd" "vlanmgrd"

# Config tools
assert_contains "usr/local/bin/sonic-cfggen" "sonic-cfggen"
assert_contains "usr/local/bin/sonic-db-cli" "sonic-db-cli"

# Redis
assert_contains "usr/bin/redis-server" "redis-server"

# FRR
assert_contains "usr/lib/frr/zebra" "FRR zebra"
assert_contains "usr/lib/frr/staticd" "FRR staticd"

# Config files
assert_contains "etc/supervisor/conf.d/supervisord.conf" "supervisord config"
assert_contains "etc/sonic/sonic_version.yml" "sonic version"

# Libraries
assert_contains "libswsscommon" "libswsscommon"
assert_contains "libhiredis" "libhiredis"
assert_contains "libyang" "libyang"

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== ALL ASSERTIONS PASSED ==="
else
    echo "=== $ERRORS ASSERTIONS FAILED ==="
    exit 1
fi
