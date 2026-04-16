#!/usr/bin/env python3
"""Post a Cloud Build step failure summary to GitHub as a commit comment.

Called from cloudbuild.yaml at the tail of each build/test step when the
step's exit code is non-zero. Uses only Python stdlib so it runs in any
step image that has python3.

Usage:
    python3 scripts/ci/post_step_failure.py <step-name> <log-path> <exit-code>

Required env:
    GITHUB_TOKEN   GitHub token with `repo` scope (via Secret Manager).
    COMMIT_SHA     Set automatically by Cloud Build.
    BUILD_ID       Set automatically by Cloud Build.

Behavior:
    - No-op when exit-code is 0.
    - No-op and exits 0 when GITHUB_TOKEN or COMMIT_SHA is missing, so the
      helper never masks the real step exit code.
    - Reads last ~30 KB of the log and posts it as a commit comment on
      baxia-lan/sonic-buildimage at COMMIT_SHA, with a link to the Cloud
      Build console page.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

REPO = "baxia-lan/sonic-buildimage"
GCP_PROJECT = "yilanji-sandbox-163694"
TAIL_BYTES = 30_000


def read_tail(path: str, limit: int) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - limit))
            return f.read().decode("utf-8", errors="replace")
    except Exception as e:
        return f"(could not read {path}: {e})"


def post_comment(token: str, sha: str, body: str) -> None:
    url = f"https://api.github.com/repos/{REPO}/commits/{sha}/comments"
    data = json.dumps({"body": body}).encode("utf-8")
    req = urllib.request.Request(
        url,
        method="POST",
        data=data,
        headers={
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
            "User-Agent": "cloudbuild-post-step-failure",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(f">>> [post-failure] Commit comment posted: HTTP {r.status}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        print(f">>> [post-failure] HTTP {e.code}: {detail}")
    except Exception as e:
        print(f">>> [post-failure] Error: {e}")


def main() -> int:
    if len(sys.argv) != 4:
        print(">>> [post-failure] Usage: post_step_failure.py <step> <log> <rc>")
        return 0

    step = sys.argv[1]
    log_path = sys.argv[2]
    try:
        rc = int(sys.argv[3])
    except ValueError:
        rc = -1

    if rc == 0:
        return 0

    token = os.environ.get("GITHUB_TOKEN") or ""
    sha = os.environ.get("COMMIT_SHA") or ""
    build_id = os.environ.get("BUILD_ID") or "unknown"

    if not token or not sha:
        print(">>> [post-failure] GITHUB_TOKEN or COMMIT_SHA missing; skip")
        return 0

    tail = read_tail(log_path, TAIL_BYTES)
    console_url = (
        f"https://console.cloud.google.com/cloud-build/builds/{build_id}"
        f"?project={GCP_PROJECT}"
    )
    body = (
        f"## Cloud Build step `{step}` FAILED (exit {rc})\n\n"
        f"[Full log in Cloud Build console]({console_url})\n\n"
        f"<details>\n<summary>Last ~30 KB of step output</summary>\n\n"
        f"```\n{tail}\n```\n</details>\n"
    )
    post_comment(token, sha, body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
