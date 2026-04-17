#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
TOOL_NAME="$(jq -r '.tool_name // empty' <<<"$INPUT")"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"

# Narrow allowlist (runs before the block list). If a command matches an
# allow pattern, it is permitted even if it would otherwise look dangerous.
ALLOW_PATTERNS=(
  '^git[[:space:]]+push[[:space:]]+origin[[:space:]]+claude[[:space:]]*$'
)
for pattern in "${ALLOW_PATTERNS[@]}"; do
  if [[ "$COMMAND" =~ $pattern ]]; then
    exit 0
  fi
done

BLOCK_PATTERNS=(
  '(^|[[:space:]])sudo([[:space:]]|$)'
  '(^|[[:space:]])rm[[:space:]]+-rf[[:space:]]+/$'
  'git[[:space:]]+push([[:space:]]|$)'
  'git[[:space:]]+remote[[:space:]]+(add|remove|rename|set-url)([[:space:]]|$)'
  'gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
  'gh[[:space:]]+repo[[:space:]]+create([[:space:]]|$)'
  'git[[:space:]]+reset[[:space:]]+--hard'
  'git[[:space:]]+clean[[:space:]]+-fdx'
  'git[[:space:]]+rebase([[:space:]]|$)'
  'git[[:space:]]+commit[[:space:]]+--amend'
  '(^|[[:space:]])rm([[:space:]].*)?(Makefile(\.[^[:space:]]+)?|[^[:space:]]+\.mk)([[:space:]]|$)'
  'git[[:space:]]+rm([[:space:]].*)?(Makefile(\.[^[:space:]]+)?|[^[:space:]]+\.mk)([[:space:]]|$)'
  'docker[[:space:]].*--privileged'
  'docker[[:space:]].*--network[=[:space:]]host'
  'docker[[:space:]].*(-v|--volume)[[:space:]]*/:'
  'docker[[:space:]].*--mount[^[:cntrl:]]*src=/([, ]|$)'
  'docker[[:space:]].*(-v|--volume)[[:space:]]*/var/run/docker\.sock:'
  'docker[[:space:]].*--mount[^[:cntrl:]]*/var/run/docker\.sock'
)

for pattern in "${BLOCK_PATTERNS[@]}"; do
  if [[ "$COMMAND" =~ $pattern ]]; then
    jq -n --arg reason "Blocked dangerous command: $COMMAND" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
  fi
done

exit 0
