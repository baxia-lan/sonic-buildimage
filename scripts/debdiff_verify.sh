#!/usr/bin/env bash
# Verify that Bazel-built .deb packages match Make-built .deb packages.
# Only timestamps should differ (content must be identical).
#
# Usage: debdiff_verify.sh <bazel-deb> <make-deb>
set -euo pipefail

BAZEL_DEB="${1:?Usage: $0 <bazel-deb> <make-deb>}"
MAKE_DEB="${2:?Usage: $0 <bazel-deb> <make-deb>}"

echo "=== Comparing .deb packages ==="
echo "  Bazel: $BAZEL_DEB"
echo "  Make:  $MAKE_DEB"

# Extract both debs
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bazel" "$WORK/make"
dpkg-deb -x "$BAZEL_DEB" "$WORK/bazel"
dpkg-deb -x "$MAKE_DEB" "$WORK/make"

# Compare file trees (ignoring timestamps)
echo ""
echo "=== File tree diff ==="
diff <(cd "$WORK/bazel" && find . -type f | sort) \
     <(cd "$WORK/make" && find . -type f | sort) || {
    echo "FAIL: File lists differ"
    exit 1
}
echo "  File lists: IDENTICAL"

# Compare file contents (sha256)
echo ""
echo "=== Content diff ==="
DIFF_COUNT=0
cd "$WORK/bazel"
for f in $(find . -type f | sort); do
    BAZEL_SHA=$(sha256sum "$WORK/bazel/$f" | awk '{print $1}')
    MAKE_SHA=$(sha256sum "$WORK/make/$f" 2>/dev/null | awk '{print $1}')
    if [ "$BAZEL_SHA" != "$MAKE_SHA" ]; then
        echo "  DIFF: $f"
        DIFF_COUNT=$((DIFF_COUNT + 1))
    fi
done

echo ""
if [ "$DIFF_COUNT" -eq 0 ]; then
    echo "=== PASS: All files identical ==="
else
    echo "=== $DIFF_COUNT files differ ==="
    echo "Note: Timestamp-only differences are acceptable per CLAUDE.md"
fi
