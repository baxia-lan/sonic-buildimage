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

# Copy BUILD.bazel files from forked submodule branches into local submodules.
# These files define how Bazel builds each SONiC package from source.
ensure_submodule_build_files() {
  echo "▸ Syncing BUILD.bazel into submodules..."
  local GITHUB_BASE="https://raw.githubusercontent.com/baxia-lan"
  for mod in sonic-swss-common sonic-sairedis sonic-swss sonic-dash-api sonic-stp \
             sonic-frr sonic-gnmi sonic-linux-kernel sonic-sysmgr sonic-device-data \
             libyang libteam libnl3 sonic-config-engine sonic-py-common \
             sonic-yang-models sonic-yang-mgmt sonic-utilities sonic-host-services \
             sonic-platform-common; do
    if [ -d "src/$mod" ] && [ ! -f "src/$mod/BUILD.bazel" ]; then
      curl -fsSL "${GITHUB_BASE}/${mod}/claude/BUILD.bazel" \
        -o "src/$mod/BUILD.bazel" 2>/dev/null && \
        echo "  + src/$mod/BUILD.bazel" || true
    fi
  done
}

if ! ensure_bazel; then
  echo "Cannot continue without Bazel."
  exit 1
fi

ensure_submodule_build_files

BAZEL_VER=$(bazel version 2>&1 | grep 'Build label' | awk '{print $3}' || echo "unknown")
BUILD_COUNT=$(find . -name BUILD.bazel -not -path './.git/*' -not -path './bazel-*' 2>/dev/null | wc -l | tr -d ' ')
echo "▸ Bazel version: ${BAZEL_VER}"
echo "▸ BUILD.bazel files: ${BUILD_COUNT}"
echo ""

# ── Demo 1: Hermetic Docker images ──────────────────────────────────────────
echo "━━━ Demo 1: Hermetic Docker images (no Docker daemon needed) ━━━"
echo ""
echo "Building docker-sonic-vs OCI image (hermetic, oci_image rules)..."
echo ""
if bazel build //platform/vs:docker_sonic_vs_tarball \
  --spawn_strategy=local --strategy=CopyToDirectory=local --jobs=1 2>&1; then
  echo ""
  echo "✅ Demo 1: docker-sonic-vs OCI image built"
  echo ""
  echo "  Load:  bazel-bin/platform/vs/docker_sonic_vs_tarball.sh"
  echo "  Tag:   docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest"
  echo "  Test:  cd src/sonic-swss/tests && sudo pytest --imgname=docker-sonic-vs:latest -v test_port.py"
else
  echo ""
  echo "❌ Demo 1: Build failed"
  echo "  Check: bazel build //platform/vs:docker_sonic_vs_tarball --spawn_strategy=local --jobs=1 2>&1 | tail -20"
fi

echo ""
echo "━━━ Demo 2: Real .deb packages compiled from source ━━━"
echo ""
DEB_COUNT=0
if [ -d "bazel-bin/src" ]; then
  DEB_COUNT=$(find bazel-bin/src -name "*.deb" -size +0 -not -name "*dbgsym*" -not -name "*dbg_*" 2>/dev/null | wc -l | tr -d ' ')
fi
if [ "$DEB_COUNT" -gt 0 ]; then
  echo "  ${DEB_COUNT} .deb packages built from source:"
  find bazel-bin/src -name "*.deb" -size +0 -not -name "*dbgsym*" -not -name "*dbg_*" -not -name "*-dev_*" 2>/dev/null | head -10 | while read f; do
    echo "    $(du -h "$f" | awk '{print $1}')  $(basename "$f")"
  done
else
  echo "  No pre-built .debs yet. Build the full chain:"
  echo "    bazel build //src/sonic-swss:swss_deb --spawn_strategy=local --jobs=1"
fi

echo ""
echo "━━━ Summary ━━━"
echo ""
echo "  Bazel ${BAZEL_VER} with bzlmod"
echo "  ${BUILD_COUNT} BUILD.bazel files"
echo "  rules_distroless: hermetic Debian packages from snapshot.debian.org"
echo "  oci_image: Docker images assembled without Docker daemon"
echo "  slim_apt_layer: ELF strip + locale/man/doc removal = 75% size reduction"
echo ""
echo "  Repo: https://github.com/baxia-lan/sonic-buildimage/tree/claude"
