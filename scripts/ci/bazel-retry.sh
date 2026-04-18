#!/bin/bash
# bazel-retry.sh — wrap a bazel command with retries on transient
# github.com / BCR 504 Gateway Timeout responses during the
# repository-rule fetch phase.
#
# Evidence trail:
#   build 30396945 on 246ddc314 — rules_oci-v2.0.0 fetch: 504
#   build 6cd2aafb on c6a6b1ff7 — rules_shell-v0.4.1 fetch: 504
#   build c5abeb1d on ac0102dee — protobuf-29.0.zip fetch: 504
#
# Bazel's --experimental_repository_downloader_retries=6 is already set
# in .bazelrc but GitHub releases CDN can 504 all 6 attempts in a row
# within a few seconds. This wrapper re-invokes bazel from scratch up to
# 3 times with 60-second spacing, which spans the typical duration of a
# GitHub releases edge degradation.
#
# Only retries on clear transient signatures (504 / IOException /
# "Build did NOT complete successfully" paired with download errors).
# Compilation errors, action failures, and test failures are NOT
# retried — they fail through immediately with the original exit code.
#
# Usage:
#   bash scripts/ci/bazel-retry.sh <bazel args...>
#
# Exits with bazel's final exit code (on first success or last failure).
set -u

MAX_ATTEMPTS="${BAZEL_RETRY_ATTEMPTS:-3}"
BACKOFF_SEC="${BAZEL_RETRY_BACKOFF:-60}"
LOG=$(mktemp /tmp/bazel-retry.XXXXXX.log)
trap 'rm -f "$LOG"' EXIT

attempt=1
while :; do
  echo "[bazel-retry] attempt ${attempt}/${MAX_ATTEMPTS}: bazel $*"
  bazel "$@" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ]; then
    echo "[bazel-retry] attempt ${attempt} succeeded (rc=0)"
    exit 0
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "[bazel-retry] attempt ${attempt} failed (rc=${rc}); no more retries"
    exit "$rc"
  fi

  if grep -qE '504 Gateway|IOException.*50[0-9]|no such package.*IOException' "$LOG"; then
    echo "[bazel-retry] attempt ${attempt} failed (rc=${rc}) with transient HTTP error; sleeping ${BACKOFF_SEC}s"
    sleep "$BACKOFF_SEC"
    attempt=$((attempt + 1))
    continue
  fi

  echo "[bazel-retry] attempt ${attempt} failed (rc=${rc}); no transient-error signature; aborting"
  exit "$rc"
done
