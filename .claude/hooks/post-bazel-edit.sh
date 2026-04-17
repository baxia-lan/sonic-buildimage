#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
FILE_PATH="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")"

[[ -n "$FILE_PATH" ]] || exit 0

case "$FILE_PATH" in
  BUILD|BUILD.bazel|*.bzl|*/BUILD|*/BUILD.bazel)
    if command -v buildifier >/dev/null 2>&1; then
      buildifier "$FILE_PATH" >/dev/null 2>&1 || true
      MESSAGE="Edited Bazel file: $FILE_PATH. buildifier was run. Re-run narrow package verification."
    else
      MESSAGE="Edited Bazel file: $FILE_PATH. buildifier is not installed, so formatting was not normalized. Re-run narrow package verification."
    fi

    jq -n \
      --arg msg "$MESSAGE" \
      '{
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: $msg
        }
      }'
    ;;
esac

exit 0
