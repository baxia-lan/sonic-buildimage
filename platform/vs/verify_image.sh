#!/usr/bin/env bash
# Verify docker-sonic-vs image has all required components for pytest.
# Run after loading the image:
#   bazel-bin/platform/vs/docker_sonic_vs_tarball.sh
#   docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest
#   ./platform/vs/verify_image.sh
set -euo pipefail

IMAGE="${1:-docker-sonic-vs:latest}"
PASS=0
FAIL=0

check() {
  local desc="$1" cmd="$2"
  if docker run --rm --entrypoint bash "$IMAGE" -c "$cmd" >/dev/null 2>&1; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Verifying $IMAGE ==="
echo ""
echo "Binaries:"
check "syncd"       "which syncd"
check "orchagent"   "which orchagent"
check "redis-server" "which redis-server"
check "supervisord" "which supervisord"
check "sonic-db-cli" "which sonic-db-cli"
check "sonic-cfggen" "which sonic-cfggen"
check "portsyncd"   "which portsyncd"
check "neighsyncd"  "which neighsyncd"
check "fpmsyncd"    "which fpmsyncd"
check "vlanmgrd"    "which vlanmgrd"
check "intfmgrd"    "which intfmgrd"

echo ""
echo "FRR:"
check "zebra"   "which zebra || test -f /usr/lib/frr/zebra"
check "bgpd"    "which bgpd || test -f /usr/lib/frr/bgpd"
check "staticd" "which staticd || test -f /usr/lib/frr/staticd"

echo ""
echo "Python:"
check "swsscommon"    "python3 -c 'import swsscommon'"
check "sonic-cfggen"  "sonic-cfggen --help >/dev/null 2>&1"

echo ""
echo "Config files:"
check "supervisord.conf" "test -s /etc/supervisor/conf.d/supervisord.conf"
check "database_config"  "test -f /etc/default/sonic-db/database_config.json"
check "sonic_version"    "test -f /etc/sonic/sonic_version.yml"
check "platform.json"    "test -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/platform.json"
check "lanemap.ini"      "test -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/Force10-S6000/lanemap.ini || test -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/SONiC-VM/lanemap.ini"
check "start.sh"         "test -x /usr/bin/start.sh"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$FAIL"
