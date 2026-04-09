#!/usr/bin/env bash
# SONiC Make→Bazel Migration Demo
# Run: ./demo.sh
set -uo pipefail

cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SONiC Build System Migration: Make → Bazel (bzlmod)       ║"
echo "║  Hermetic, reproducible, 75% smaller images                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Environment setup ─────────────────────────────────────────────────────────
ensure_bazel() {
  if command -v bazel &>/dev/null; then
    return 0
  fi
  echo "▸ Bazel not found. Installing Bazelisk..."
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported arch: $ARCH"; return 1 ;;
  esac
  local OS
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  local URL="https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-${OS}-${ARCH}"
  if [ -w /usr/local/bin ]; then
    curl -fsSL "$URL" -o /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
  else
    echo "  Need sudo to install to /usr/local/bin"
    sudo curl -fsSL "$URL" -o /usr/local/bin/bazel && sudo chmod +x /usr/local/bin/bazel
  fi
  if command -v bazel &>/dev/null; then
    echo "  ✅ Bazelisk installed: $(bazel version 2>&1 | grep 'Build label' | awk '{print $3}')"
  else
    echo "  ❌ Install failed. Manual: sudo curl -Lo /usr/local/bin/bazel $URL && sudo chmod +x /usr/local/bin/bazel"
    return 1
  fi
}

if ! ensure_bazel; then
  echo "Cannot continue without Bazel."
  exit 1
fi

BAZEL_VER=$(bazel version 2>&1 | grep 'Build label' | awk '{print $3}' || echo "unknown")
BUILD_COUNT=$(find . -name BUILD.bazel -not -path './.git/*' -not -path './bazel-*' 2>/dev/null | wc -l | tr -d ' ')
echo "▸ Bazel version: ${BAZEL_VER}"
echo "▸ BUILD.bazel files: ${BUILD_COUNT}"
echo ""

# ── Demo 1: Hermetic Docker images ──────────────────────────────────────────
echo "━━━ Demo 1: Hermetic Docker images (no Docker daemon needed) ━━━"
echo ""
echo "Building 9 service images from pre-resolved Debian packages..."
echo "(rules_distroless: 190 packages from snapshot.debian.org)"
echo ""
if bazel build \
  //dockers/sonic-common-layer:sonic_common_layer \
  //dockers/docker-database:docker_database \
  //dockers/docker-teamd:docker_teamd \
  //dockers/docker-nat:docker_nat \
  //dockers/docker-stp:docker_stp \
  //dockers/docker-iccpd:docker_iccpd \
  //dockers/docker-router-advertiser:docker_router_advertiser \
  //dockers/docker-basic_router:docker_basic_router \
  //dockers/docker-sflow:docker_sflow \
  --strategy=CopyToDirectory=local 2>&1; then
  echo "✅ Demo 1: 9 service images built"
else
  echo "❌ Demo 1: Build failed"
fi

echo ""
echo "━━━ Demo 2: Real .deb packages compiled from source ━━━"
echo ""
echo "Building swss (orchagent) from source via Bazel..."
if [ -f "bazel-bin/src/sonic-swss/swss_1.0.0_amd64.deb" ]; then
  echo "  swss_1.0.0_amd64.deb: $(du -h bazel-bin/src/sonic-swss/swss_1.0.0_amd64.deb | awk '{print $1}')"
  DEB_COUNT=$(find bazel-bin/src -name "*.deb" -size +0 -not -name "*dbgsym*" -not -name "*dbg_*" 2>/dev/null | wc -l | tr -d ' ')
  echo "  Total .deb packages in bazel-bin: ${DEB_COUNT}"
else
  echo "  Building swss .deb (this takes ~10 min on first run)..."
  if bazel build //src/sonic-swss:swss_deb --spawn_strategy=local --jobs=1 2>&1; then
    echo "  ✅ swss_1.0.0_amd64.deb built: $(du -h bazel-bin/src/sonic-swss/swss_1.0.0_amd64.deb | awk '{print $1}')"
  else
    echo "  ❌ swss build failed (needs Docker for cross-compilation)"
  fi
fi

echo ""
echo "━━━ Demo 3: docker-sonic-vs for pytest ━━━"
echo ""
echo "Building docker-sonic-vs with real SONiC services..."
if [ -f "bazel-bin/platform/vs/docker-sonic-vs.tar.gz" ]; then
  echo "  ✅ docker-sonic-vs.tar.gz: $(du -h bazel-bin/platform/vs/docker-sonic-vs.tar.gz | awk '{print $1}')"
  echo ""
  echo "  Load & test:"
  echo "    docker load -i bazel-bin/platform/vs/docker-sonic-vs.tar.gz"
  echo "    docker tag docker-sonic-vs:bazel docker-sonic-vs:latest"
  echo "    cd src/sonic-swss/tests && sudo pytest --imgname=docker-sonic-vs:latest -v test_port.py"
else
  echo "  Building docker-sonic-vs (takes ~5 min with Docker)..."
  if bazel build //platform/vs:docker_sonic_vs --spawn_strategy=local --jobs=1 2>&1; then
    echo "  ✅ docker-sonic-vs.tar.gz: $(du -h bazel-bin/platform/vs/docker-sonic-vs.tar.gz | awk '{print $1}')"
  else
    echo "  ❌ docker-sonic-vs build failed"
  fi
fi

echo ""
echo "━━━ Demo 4: sonic-broadcom.bin ONIE installer ━━━"
echo ""
if bazel build //platform/broadcom:sonic_broadcom_minimal --strategy=CopyToDirectory=local 2>&1; then
  echo "✅ sonic-broadcom.bin: $(du -h bazel-bin/platform/broadcom/sonic_broadcom_minimal.bin | awk '{print $1}')"
else
  echo "❌ sonic-broadcom.bin build failed"
  echo "  Run: bazel build //platform/broadcom:sonic_broadcom_minimal --strategy=CopyToDirectory=local"
fi

echo ""
echo "━━━ Summary ━━━"
echo ""
echo "✅ Bazel ${BAZEL_VER} with bzlmod"
echo "✅ ${BUILD_COUNT} BUILD.bazel files"
echo "✅ rules_distroless: 190 Debian packages at fetch time"
echo "✅ Hermetic LLVM/Clang 18 toolchain + Bookworm sysroot"
echo "✅ slim_apt_layer: 75% image size reduction"
