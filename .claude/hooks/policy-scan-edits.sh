#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
FILE_PATH="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")"
[[ -n "$FILE_PATH" ]] || exit 0

WARNINGS=()

case "$FILE_PATH" in
  cloudbuild.yaml|acceptance/*|rules/bazel/deb/*|src/*/BUILD.bazel|src/*/*/BUILD.bazel|platform/*/BUILD.bazel|platform/*/*/BUILD.bazel|CLAUDE.md|EXECUTION_PLAN.md)
    if [[ -f "$FILE_PATH" ]]; then
      grep -nE 'apt-get|apk add|yum install|dnf install|curl[[:space:]].*raw.githubusercontent.com|docker run|no-sandbox|unset[[:space:]]+SOURCE_DATE_EPOCH|git checkout[[:space:]][0-9a-f]{7,40}' "$FILE_PATH" >/tmp/claude_policy_scan_hits.$$ || true
      if [[ -s /tmp/claude_policy_scan_hits.$$ ]]; then
        HITS="$(sed 's/"/\"/g' /tmp/claude_policy_scan_hits.$$ | head -n 20)"
        WARNINGS+=("Policy scan warning for $FILE_PATH. High-risk patterns detected (first hits): $HITS")
      fi
      rm -f /tmp/claude_policy_scan_hits.$$
    fi
    ;;
esac

git diff --name-status -- 'Makefile*' ':(glob)**/*.mk' >/tmp/claude_make_status_hits.$$ 2>/dev/null || true
if [[ -s /tmp/claude_make_status_hits.$$ ]]; then
  if grep -qE '^(D|R[0-9]+)[[:space:]]' /tmp/claude_make_status_hits.$$; then
    HITS="$(sed 's/"/\"/g' /tmp/claude_make_status_hits.$$ | head -n 20)"
    WARNINGS+=("Make preservation warning: deleted or renamed Make-owned paths detected in current diff: $HITS")
  fi
fi
rm -f /tmp/claude_make_status_hits.$$

if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
  MSG="$(printf '%s ' "${WARNINGS[@]}")"
  jq -n     --arg msg "$MSG"     '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $msg
      }
    }'
fi

exit 0
