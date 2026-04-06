#!/usr/bin/env bash
# Verify Bazel-produced .debs match Make-produced .debs.
#
# Usage: ./tools/debdiff_verify.sh [package_name]
#   e.g.: ./tools/debdiff_verify.sh sonic-swss-common
#
# Compares: file lists, control metadata, binary sizes.
# Timestamps are expected to differ (SOURCE_DATE_EPOCH handling).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="$REPO_ROOT/target/debdiff"
mkdir -p "$REPORT_DIR"

PKG="${1:-sonic-swss-common}"

echo "=== debdiff verification for $PKG ==="

# Find Bazel-produced debs
BAZEL_DEBS=$(find "$REPO_ROOT/bazel-bin/src/$PKG" -name "*.deb" -not -name "*dbgsym*" -not -name "*dbg_*" 2>/dev/null)
if [ -z "$BAZEL_DEBS" ]; then
    echo "ERROR: No Bazel debs found for $PKG"
    echo "Run: bazel build //src/$PKG:${PKG//-/_}_debs --spawn_strategy=local --jobs=1"
    exit 1
fi

echo ""
echo "Bazel debs found:"
for deb in $BAZEL_DEBS; do
    echo "  $(basename $deb) ($(du -h "$deb" | cut -f1))"
done

# Find Make-produced debs (if they exist)
MAKE_DEB_DIR="$REPO_ROOT/target/debs/bookworm"
if [ ! -d "$MAKE_DEB_DIR" ]; then
    MAKE_DEB_DIR="$REPO_ROOT/target/debs/bullseye"
fi

PASS=0
FAIL=0
SKIP=0

for bazel_deb in $BAZEL_DEBS; do
    base=$(basename "$bazel_deb")
    make_deb="$MAKE_DEB_DIR/$base"
    report="$REPORT_DIR/${base%.deb}.diff"

    echo ""
    echo "--- $base ---"

    if [ ! -f "$make_deb" ]; then
        echo "  SKIP: No Make-produced deb at $make_deb"
        echo "  (Build with Make first: make target/debs/bookworm/$base)"
        SKIP=$((SKIP + 1))

        # Self-check: verify the Bazel deb is valid
        echo "  Bazel deb self-check:"
        docker run --rm -v "$bazel_deb:/deb:ro" debian:bookworm-slim \
            bash -c 'dpkg-deb -I /deb 2>&1 | head -5; echo "Files: $(dpkg-deb -c /deb | wc -l)"' 2>&1 | sed 's/^/    /'
        continue
    fi

    echo "  Bazel: $(du -h "$bazel_deb" | cut -f1)"
    echo "  Make:  $(du -h "$make_deb" | cut -f1)"

    # Run debdiff inside Docker (needs devscripts)
    docker run --rm \
        -v "$bazel_deb:/bazel.deb:ro" \
        -v "$make_deb:/make.deb:ro" \
        -e DEBIAN_FRONTEND=noninteractive \
        debian:bookworm-slim \
        bash -c '
            apt-get update -qq && apt-get install -y -qq --no-install-recommends devscripts 2>&1 | tail -1
            echo "=== debdiff ==="
            debdiff /make.deb /bazel.deb 2>&1 || true
            echo ""
            echo "=== File count comparison ==="
            echo "Make files:  $(dpkg-deb -c /make.deb | wc -l)"
            echo "Bazel files: $(dpkg-deb -c /bazel.deb | wc -l)"
            echo ""
            echo "=== Size comparison ==="
            echo "Make size:  $(dpkg-deb -I /make.deb | grep "Installed-Size")"
            echo "Bazel size: $(dpkg-deb -I /bazel.deb | grep "Installed-Size")"
        ' 2>&1 | tee "$report" | sed 's/^/  /'

    # Check if debdiff found meaningful differences
    if grep -q "^Files\|^Binary" "$report" 2>/dev/null; then
        echo "  RESULT: DIFFERENCES FOUND (see $report)"
        FAIL=$((FAIL + 1))
    else
        echo "  RESULT: PASS (no meaningful differences)"
        PASS=$((PASS + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP (no Make baseline available)"
echo "  Reports: $REPORT_DIR/"
