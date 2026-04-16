#!/bin/bash
# Diagnostic wrapper around scripts/ci/post_step_failure.py.
#
# Called from each Cloud Build step after the step's pipeline completes:
#     ( ... ) 2>&1 | tee "$LOG"
#     RC=${PIPESTATUS[0]}
#     bash scripts/ci/post_step_failure.sh "$STEP" "$LOG" "$RC" || true
#     exit $RC
#
# Always prints diagnostic status lines to the Cloud Build console so that
# when the Python helper cannot run (missing python3, missing token, etc.)
# the failure mode is visible in the step log itself.
#
# Never propagates a non-zero exit; callers `|| true` this wrapper so a
# reporting failure never masks the underlying step failure.
set -u

STEP="${1:-unknown}"
LOG="${2:-}"
RC="${3:-0}"

TOK_STATE="EMPTY"
[ -n "${GITHUB_TOKEN:-}" ] && TOK_STATE="SET(len=${#GITHUB_TOKEN})"
LOG_STATE="NO"
[ -f "$LOG" ] && LOG_STATE="YES(size=$(stat -c%s "$LOG" 2>/dev/null || echo 0))"
SCRIPT_STATE="NO"
[ -f scripts/ci/post_step_failure.py ] && SCRIPT_STATE="YES"
PY_STATE="NO"
command -v python3 >/dev/null 2>&1 && PY_STATE="YES"

echo "[post-hook] step=$STEP rc=$RC token=$TOK_STATE log=$LOG_STATE ($LOG) script=$SCRIPT_STATE python3=$PY_STATE sha=${COMMIT_SHA:-unset} build=${BUILD_ID:-unset}"

if [ "$RC" -eq 0 ]; then
  echo "[post-hook] rc=0, nothing to report"
  exit 0
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[post-hook] SKIP: GITHUB_TOKEN empty. Log tail:"
  tail -c 4000 "$LOG" 2>/dev/null || echo "(no log available)"
  exit 0
fi

if [ ! -f scripts/ci/post_step_failure.py ]; then
  echo "[post-hook] SKIP: scripts/ci/post_step_failure.py missing. Log tail:"
  tail -c 4000 "$LOG" 2>/dev/null || echo "(no log available)"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[post-hook] python3 missing, attempting apt-get install..."
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq python3 >/dev/null 2>&1 || \
    apk add --no-cache python3 >/dev/null 2>&1 || true
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[post-hook] python3 STILL missing; cannot post commit comment. Log tail:"
  tail -c 4000 "$LOG" 2>/dev/null || echo "(no log available)"
  exit 0
fi

echo "[post-hook] posting commit comment to GitHub..."
python3 scripts/ci/post_step_failure.py "$STEP" "$LOG" "$RC" && \
  echo "[post-hook] posted OK" || \
  echo "[post-hook] python helper exited non-zero (RC=$?)"
exit 0
