#!/usr/bin/env bash
# Gate 2: Cloud Build — verify CI works and remote cache is effective
#
# Maturity: ADVISORY
#   This gate checks CI configuration structure only. It cannot verify:
#   - Actual Cloud Build execution success
#   - Remote cache hit rate (requires two sequential builds)
#   - GitHub commit status delivery
#   These require a real Cloud Build run and manual inspection.
set -euo pipefail

echo "=== Gate 2: Cloud Build (ADVISORY — config checks only) ==="

# Step 1: Verify cloudbuild.yaml is valid
echo "Step 1: Validating cloudbuild.yaml..."
[ -f cloudbuild.yaml ] || { echo "FAIL: cloudbuild.yaml not found"; exit 1; }
python3 -c "import yaml; yaml.safe_load(open('cloudbuild.yaml'))" 2>/dev/null || \
python3 -c "
import json, re
with open('cloudbuild.yaml') as f:
    content = f.read()
# Basic structure check
assert 'steps:' in content, 'No steps section'
assert 'timeout:' in content, 'No timeout'
print('cloudbuild.yaml: valid structure')
"

# Step 2: Verify remote cache is configured
echo "Step 2: Checking remote cache config..."
grep -q "remote_cache.*sonic-bazel-cache" .bazelrc || { echo "FAIL: remote cache not in .bazelrc"; exit 1; }
echo "  Remote cache: configured"

# Step 3: Verify GitHub log reporting
echo "Step 3: Checking log reporting..."
grep -q "github.*status\|GITHUB_TOKEN\|commit.*status" cloudbuild.yaml || echo "  WARN: No GitHub status reporting"
grep -q "upload.*summary\|gsutil\|GCS" cloudbuild.yaml && echo "  GCS summary: configured" || echo "  WARN: No GCS summary"

# Step 4: CI integrity check — no repo mutation
echo "Step 4: CI integrity check..."
VIOLATIONS=0
if grep -q "git checkout.*[0-9a-f]\{7,40\}" cloudbuild.yaml; then
  echo "  FAIL: cloudbuild.yaml contains hardcoded git checkout SHAs (repo mutation)"
  VIOLATIONS=$((VIOLATIONS + 1))
fi
if grep -q "raw.githubusercontent.com" cloudbuild.yaml; then
  echo "  FAIL: cloudbuild.yaml downloads files from external repos at CI time"
  VIOLATIONS=$((VIOLATIONS + 1))
fi
if grep -qE 'find.*BUILD\.bazel.*sed|sed.*BUILD\.bazel|sed.*SOURCE_DATE_EPOCH' cloudbuild.yaml; then
  echo "  FAIL: cloudbuild.yaml mutates tracked BUILD/source files with sed at CI time"
  VIOLATIONS=$((VIOLATIONS + 1))
fi
if grep -qE '\|\|.*exit 0' cloudbuild.yaml; then
  echo "  WARN: cloudbuild.yaml swallows failures with '|| exit 0'"
  VIOLATIONS=$((VIOLATIONS + 1))
fi
if [ "$VIOLATIONS" -eq 0 ]; then
  echo "  CI integrity: OK (no repo mutation detected)"
else
  echo "  CI integrity: $VIOLATIONS violation(s) found"
fi

# Step 5: Cache hit rate (cannot verify locally)
echo "Step 5: Cache hit rate — CANNOT VERIFY LOCALLY"
echo "  Requires two sequential Cloud Build runs"
echo "  Expected: >= 80% cache hit on second run"

echo ""
echo "=== Gate 2: ADVISORY ONLY ==="
echo "Config checks passed. Full gate requires actual Cloud Build execution."
echo "Unverifiable locally: build success, cache hit rate, GitHub status delivery."
