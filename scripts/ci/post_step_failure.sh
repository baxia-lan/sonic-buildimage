#!/bin/bash
# Post a Cloud Build step failure summary (or a heartbeat) to GitHub as a
# commit comment. Uses pure bash + curl so it works in any step image that
# has a POSIX bash and curl — no python runtime dependency.
#
# Usage:
#     bash scripts/ci/post_step_failure.sh <step> <log> <rc>
#     bash scripts/ci/post_step_failure.sh --start <step>
#
# The first form is the failure reporter: called by every Cloud Build step
# after the step's pipeline completes, logs the last ~30 KB of the step log
# as a commit comment, and always returns 0 so a reporting failure cannot
# mask the real step exit.
#
# The second form is a heartbeat: proves the step started and the
# GITHUB_TOKEN secret is wired through correctly.
#
# Environment:
#     GITHUB_TOKEN   — from Cloud Build secretEnv
#     COMMIT_SHA     — Cloud Build built-in
#     BUILD_ID       — Cloud Build built-in
set -u

REPO="baxia-lan/sonic-buildimage"
GCP_PROJECT="yilanji-sandbox-163694"

if [ "${1:-}" = "--start" ]; then
  MODE="start"
  STEP="${2:-unknown}"
  LOG=""
  RC=0
else
  MODE="end"
  STEP="${1:-unknown}"
  LOG="${2:-}"
  RC="${3:-0}"
fi

TOK_STATE="EMPTY"
[ -n "${GITHUB_TOKEN:-}" ] && TOK_STATE="SET(len=${#GITHUB_TOKEN})"
SHA_STATE="${COMMIT_SHA:-UNSET}"
BID_STATE="${BUILD_ID:-UNSET}"

echo "[post-hook] mode=$MODE step=$STEP rc=$RC token=$TOK_STATE sha=$SHA_STATE build=$BID_STATE"

# Never post in success+end mode — would spam comments
if [ "$MODE" = "end" ] && [ "$RC" -eq 0 ]; then
  echo "[post-hook] rc=0, nothing to post"
  exit 0
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "[post-hook] SKIP: GITHUB_TOKEN empty"
  if [ -n "$LOG" ] && [ -f "$LOG" ]; then
    echo "[post-hook] log tail:"
    tail -c 4000 "$LOG" 2>/dev/null || true
  fi
  exit 0
fi
if [ -z "${COMMIT_SHA:-}" ]; then
  echo "[post-hook] SKIP: COMMIT_SHA empty"
  exit 0
fi

CONSOLE_URL="https://console.cloud.google.com/cloud-build/builds/${BUILD_ID:-unknown}?project=${GCP_PROJECT}"

# Build the JSON body.
# We construct the body as a single JSON string and pipe through Python
# when available (safest for embedded quotes, newlines, binary bytes), and
# fall back to a best-effort bash escape when python3 is missing.
if [ "$MODE" = "start" ]; then
  TEXT="Cloud Build step \`$STEP\` STARTED. Build: [$BUILD_ID]($CONSOLE_URL)"
  BODY_PYTHON='import json, os; print(json.dumps({"body": os.environ["TEXT"]}))'
  if command -v python3 >/dev/null 2>&1; then
    BODY=$(TEXT="$TEXT" python3 -c "$BODY_PYTHON")
  else
    # No embedded quotes/newlines in TEXT for start mode, safe to inline.
    BODY="{\"body\": \"$TEXT\"}"
  fi
else
  TAIL=""
  if [ -n "$LOG" ] && [ -f "$LOG" ]; then
    TAIL=$(tail -c 30000 "$LOG" 2>/dev/null || true)
  fi
  [ -z "$TAIL" ] && TAIL="(no log available)"
  if command -v python3 >/dev/null 2>&1; then
    BODY=$(STEP="$STEP" RC="$RC" CONSOLE_URL="$CONSOLE_URL" TAIL="$TAIL" python3 -c '
import json, os
step = os.environ["STEP"]
rc = os.environ["RC"]
console = os.environ["CONSOLE_URL"]
tail = os.environ["TAIL"]
body = (
    "## Cloud Build step `" + step + "` FAILED (exit " + rc + ")\n\n"
    "[Full log in Cloud Build console](" + console + ")\n\n"
    "<details>\n<summary>Last ~30 KB of step output</summary>\n\n"
    "```\n" + tail + "\n```\n</details>\n"
)
print(json.dumps({"body": body}))
')
  else
    # Minimal bash-only JSON escape: backslashes, quotes, newlines.
    # Good enough for diagnostic log tails; not JSON-safe for arbitrary bytes.
    ESC_TAIL=$(printf '%s' "$TAIL" | awk '{gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\\n", $0}')
    BODY="{\"body\": \"## Cloud Build step \`$STEP\` FAILED (exit $RC)\\n\\n[console]($CONSOLE_URL)\\n\\n\`\`\`\\n$ESC_TAIL\\n\`\`\`\"}"
  fi
fi

# Primary channel: commit comment with full log tail.
HTTP_CODE=$(curl -sS -o /tmp/post-response.txt -w "%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  -H "User-Agent: cloudbuild-post-step-failure" \
  "https://api.github.com/repos/${REPO}/commits/${COMMIT_SHA}/comments" \
  -d "$BODY" 2>&1)
CURL_RC=$?
if [ "$CURL_RC" -eq 0 ] && [ "$HTTP_CODE" = "201" ]; then
  echo "[post-hook] commit comment posted OK (HTTP $HTTP_CODE)"
else
  echo "[post-hook] commit comment POST failed (curl_rc=$CURL_RC http_code=$HTTP_CODE)"
  head -c 500 /tmp/post-response.txt 2>/dev/null || true
  echo ""
fi

# Secondary channel: per-step commit status. The GITHUB_TOKEN scope known
# to work for this repo is commit statuses (proven by github-status-pending).
# Even if the commit comment POST above 403s due to scope limits, a status
# update still reaches the GitHub surface and is visible via the statuses
# API without authentication.
if [ "$MODE" = "start" ]; then
  STATUS_STATE="pending"
  STATUS_DESC="started"
else
  if [ "$RC" -eq 0 ]; then
    STATUS_STATE="success"
    STATUS_DESC="passed"
  else
    STATUS_STATE="failure"
    STATUS_DESC="rc=$RC"
  fi
fi
STATUS_DESC="${STATUS_DESC}; comment_http=${HTTP_CODE}"
[ ${#STATUS_DESC} -gt 130 ] && STATUS_DESC="${STATUS_DESC:0:130}"
STATUS_BODY="{\"state\":\"$STATUS_STATE\",\"description\":\"$STATUS_DESC\",\"context\":\"cloud-build/$STEP\",\"target_url\":\"$CONSOLE_URL\"}"
STATUS_HTTP=$(curl -sS -o /tmp/status-response.txt -w "%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  -H "User-Agent: cloudbuild-post-step-failure" \
  "https://api.github.com/repos/${REPO}/statuses/${COMMIT_SHA}" \
  -d "$STATUS_BODY" 2>&1)
if [ "$STATUS_HTTP" = "201" ]; then
  echo "[post-hook] status posted OK (HTTP $STATUS_HTTP ctx=cloud-build/$STEP)"
else
  echo "[post-hook] status POST failed (http=$STATUS_HTTP)"
  head -c 300 /tmp/status-response.txt 2>/dev/null || true
  echo ""
fi
exit 0
