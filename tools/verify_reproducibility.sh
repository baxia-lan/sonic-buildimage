#!/usr/bin/env bash
# Verify build reproducibility: two clean builds must produce identical output.
#
# Usage: ./tools/verify_reproducibility.sh [target]
#   e.g.: ./tools/verify_reproducibility.sh //src/sonic-swss-common:swss_common_debs
set -euo pipefail

TARGET="${1:-//src/sonic-swss-common:swss_common_debs}"
REPORT_DIR="$(pwd)/target/reproducibility"
mkdir -p "$REPORT_DIR"

echo "=== Reproducibility verification for $TARGET ==="
echo ""

# Build 1
echo "--- Build 1 ---"
bazel clean --expunge 2>/dev/null
bazel build "$TARGET" --spawn_strategy=local --jobs=1 2>&1 | tail -3
BUILD1_DIR="$REPORT_DIR/build1"
mkdir -p "$BUILD1_DIR"
for f in $(bazel cquery "$TARGET" --output=files 2>/dev/null); do
    cp "$f" "$BUILD1_DIR/" 2>/dev/null || true
done
echo "Build 1 outputs:"
ls -lh "$BUILD1_DIR"/*.deb 2>/dev/null | head -5

# Checksum build 1
(cd "$BUILD1_DIR" && sha256sum *.deb 2>/dev/null | sort) > "$REPORT_DIR/build1.sha256"

# Build 2
echo ""
echo "--- Build 2 ---"
bazel clean --expunge 2>/dev/null
bazel build "$TARGET" --spawn_strategy=local --jobs=1 2>&1 | tail -3
BUILD2_DIR="$REPORT_DIR/build2"
mkdir -p "$BUILD2_DIR"
for f in $(bazel cquery "$TARGET" --output=files 2>/dev/null); do
    cp "$f" "$BUILD2_DIR/" 2>/dev/null || true
done
echo "Build 2 outputs:"
ls -lh "$BUILD2_DIR"/*.deb 2>/dev/null | head -5

# Checksum build 2
(cd "$BUILD2_DIR" && sha256sum *.deb 2>/dev/null | sort) > "$REPORT_DIR/build2.sha256"

# Compare
echo ""
echo "=== Comparison ==="
if diff "$REPORT_DIR/build1.sha256" "$REPORT_DIR/build2.sha256" >/dev/null 2>&1; then
    echo "PASS: Builds are bit-identical"
    cat "$REPORT_DIR/build1.sha256"
else
    echo "FAIL: Builds differ"
    diff "$REPORT_DIR/build1.sha256" "$REPORT_DIR/build2.sha256" || true
fi
