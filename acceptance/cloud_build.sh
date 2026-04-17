#!/usr/bin/env bash
# Gate 2: Cloud Build — verify CI config is truthful and upstreamable
#
# Maturity: ADVISORY
#   This gate cannot run Cloud Build from a sandboxed bazel test. It
#   validates the checked-in cloudbuild.yaml contract against repo rules
#   so that a Cloud Build run has a plausible chance of succeeding and
#   the result is visible on GitHub.
#
#   Full Gate 2 truth requires:
#     - A real Cloud Build execution (push triggers it)
#     - GitHub commit status `cloud-build/bazel` = success
#     - Remote cache hit rate observable on a second build
#   Those are checked out-of-band by reading commit-status API and
#   comparing two consecutive build timings.
set -euo pipefail

if [ -n "${TEST_SRCDIR:-}" ]; then
  WS="${TEST_SRCDIR}/_main"
  [ -d "$WS" ] || WS="${TEST_SRCDIR}/$(ls "${TEST_SRCDIR}" | head -1)"
else
  WS="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
fi
cd "$WS"

FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }
warn() { echo "  WARN: $*"; }
ok()   { echo "  OK:   $*"; }

echo "=== Gate 2: Cloud Build (ADVISORY — config contract checks only) ==="

# 1. cloudbuild.yaml exists and parses
echo "Step 1: Parsing cloudbuild.yaml..."
[ -f cloudbuild.yaml ] || { echo "FAIL: cloudbuild.yaml not found in $WS"; exit 1; }
if command -v python3 >/dev/null; then
  python3 - "$WS/cloudbuild.yaml" <<'PY' || { echo "FAIL: cloudbuild.yaml invalid"; exit 1; }
import sys
try:
    import yaml
    doc = yaml.safe_load(open(sys.argv[1]))
except ImportError:
    # pyyaml not available; do basic text check
    content = open(sys.argv[1]).read()
    assert 'steps:' in content, 'no steps:'
    assert 'timeout:' in content, 'no timeout:'
    print("cloudbuild.yaml: basic text structure OK (pyyaml absent)")
    sys.exit(0)
assert isinstance(doc, dict), 'not a mapping'
assert 'steps' in doc, 'no steps'
assert isinstance(doc['steps'], list) and len(doc['steps']) > 0, 'empty steps'
print(f"cloudbuild.yaml: {len(doc['steps'])} steps, timeout={doc.get('timeout', '?')}")
PY
fi
ok "cloudbuild.yaml parses"

# 2. Essential Gate-1 pipeline steps present
echo "Step 2: Verifying Gate 1 pipeline steps..."
REQUIRED_STEPS=(
  "build-orchagent"
  "build-docker-sonic-vs"
  "verify-docker-sonic-vs"
  "pytest-vs"
)
for s in "${REQUIRED_STEPS[@]}"; do
  if grep -q "id: \"$s\"" cloudbuild.yaml; then
    ok "step: $s"
  else
    fail "missing required step: $s"
  fi
done

# 3. Remote cache wired
echo "Step 3: Checking remote cache config..."
grep -q "remote_cache.*sonic-bazel-cache" .bazelrc \
  && ok "remote_cache in .bazelrc" \
  || fail "remote_cache not in .bazelrc"
grep -q -- "--config=ci" cloudbuild.yaml \
  && ok "steps use --config=ci (picks up remote_cache)" \
  || fail "no --config=ci usage in cloudbuild.yaml"

# 4. GitHub status reporting
echo "Step 4: Checking GitHub status reporting..."
grep -q "api.github.com/repos.*statuses" cloudbuild.yaml \
  && ok "GitHub statuses POST wired" \
  || fail "no GitHub statuses POST"
grep -q "post_step_failure.sh" cloudbuild.yaml \
  && ok "per-step failure reporter wired" \
  || warn "no per-step failure reporter"

# 5. Artifacts/summary visibility
echo "Step 5: Checking artifact visibility..."
grep -q "gsutil cp" cloudbuild.yaml \
  && ok "GCS summary upload present" \
  || warn "no GCS summary upload"
grep -qE "^artifacts:" cloudbuild.yaml \
  && ok "Cloud Build artifacts section present" \
  || warn "no artifacts: section (artifacts won't be uploaded to GCS)"

# 6. CI integrity — no repo mutation, no fake green
echo "Step 6: CI integrity..."
if grep -q "git checkout.*[0-9a-f]\{7,40\}" cloudbuild.yaml; then
  fail "contains hardcoded git checkout SHAs (repo mutation)"
fi
if grep -q "raw.githubusercontent.com" cloudbuild.yaml; then
  fail "downloads files from external repos at CI time"
fi
if grep -qE 'find.*BUILD\.bazel.*sed|sed.*BUILD\.bazel|sed.*SOURCE_DATE_EPOCH' cloudbuild.yaml; then
  fail "mutates tracked BUILD files with sed at CI time"
fi
# Step-level exit swallowing: allow `|| true` inside diagnostic tails, but
# flag explicit `|| exit 0` and `continue-on-error` patterns.
if grep -qE '\|\|[[:space:]]*exit 0' cloudbuild.yaml; then
  fail "swallows failure with '|| exit 0'"
fi
if grep -q "continue-on-error" cloudbuild.yaml; then
  fail "contains continue-on-error (fake green)"
fi
# Every step must propagate its own failure. Look for `exit \$\$RC` pattern
# used in the step wrappers — the post-step-failure hook must not mask it.
if ! grep -q 'exit \$\$RC' cloudbuild.yaml; then
  warn "no 'exit \$RC' propagation pattern found in steps (may mask failures)"
fi
[ "$FAIL" -eq 0 ] && ok "no CI-integrity violations"

# 7. Make preservation
#   Under `bazel test` the sandbox only sees files declared in data =; the
#   Makefile is exported so it is reachable. The `rules/` dir is not part
#   of runfiles, so its presence is advisory here (checked at source by
#   the policy-scan hook instead).
echo "Step 7: Make preservation..."
[ -f Makefile ] && ok "top-level Makefile present" || fail "top-level Makefile missing"
if [ -d rules ]; then
  ok "rules/ dir present (Make recipes)"
else
  warn "rules/ dir not in runfiles (advisory; source check covers this)"
fi

# 8. Hermeticity posture
echo "Step 8: Hermeticity posture..."
grep -q "^build --sandbox_default_allow_network=false" .bazelrc \
  && ok "sandbox_default_allow_network=false default in .bazelrc" \
  || fail "sandbox_default_allow_network not defaulted false in .bazelrc"

echo ""
echo "=== Gate 2: contract check summary ==="
if [ "$FAIL" -eq 0 ]; then
  echo "PASS (advisory): cloudbuild.yaml contract is internally consistent."
  echo ""
  echo "Runtime truth (unverifiable from bazel test):"
  echo "  - Push to 'claude' triggers Cloud Build"
  echo "  - GitHub status 'cloud-build/bazel' reports success/failure"
  echo "  - Cache hit rate visible across two consecutive builds"
  echo "  Inspect via:"
  echo "    gh api repos/baxia-lan/sonic-buildimage/commits/<sha>/status"
  echo "    gsutil cat gs://sonic-bazel-cache/ci-results/<BUILD_ID>/summary.txt"
  exit 0
else
  echo "FAIL: $FAIL contract violation(s)"
  exit 1
fi
