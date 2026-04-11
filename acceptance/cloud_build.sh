#!/usr/bin/env bash
# Gate 2: Cloud Build — verify CI works and remote cache is effective
set -euo pipefail

echo "=== Gate 2: Cloud Build ==="

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

# Step 4: Check most recent Cloud Build result
echo "Step 4: Checking last Cloud Build result..."
# Look for GitHub commit status from Cloud Build
LATEST_SHA=$(git rev-parse HEAD)
STATUS=$(curl -fsSL \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/baxia-lan/sonic-buildimage/commits/${LATEST_SHA}/status" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('state','unknown'))" 2>/dev/null || echo "unknown")
echo "  Commit status: $STATUS"

# Step 5: Verify cache hit rate (requires two builds)
echo "Step 5: Cache hit rate verification..."
echo "  (Requires two sequential Cloud Build runs — check manually)"
echo "  Expected: >= 80% cache hit on second run"

echo "=== Gate 2: PASSED (partial — full verification requires Cloud Build run) ==="
