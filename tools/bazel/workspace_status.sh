#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

repo_digest="$(
python3 - "${workspace_root}" <<'PY'
import hashlib
import pathlib
import subprocess
import sys


def hash_repo(root: pathlib.Path, digest: hashlib._hashlib.HASH) -> None:
    entries = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--stage", "-z"],
        stderr = subprocess.DEVNULL,
    ).split(b"\0")

    for entry in entries:
        if not entry:
            continue

        meta, rel_path = entry.split(b"\t", 1)
        mode, git_sha, _stage = meta.split()
        rel_path_str = rel_path.decode("utf-8")
        abs_path = root / rel_path_str

        digest.update(str(root).encode("utf-8"))
        digest.update(b"\0")
        digest.update(mode)
        digest.update(b"\0")
        digest.update(git_sha)
        digest.update(b"\0")
        digest.update(rel_path)
        digest.update(b"\0")

        if mode == b"160000":
            if abs_path.is_dir():
                hash_repo(abs_path, digest)
            else:
                digest.update(b"UNINITIALIZED_SUBMODULE")
                digest.update(b"\0")
            continue

        if not abs_path.is_file():
            digest.update(b"MISSING_FILE")
            digest.update(b"\0")
            continue

        with abs_path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")


sha256 = hashlib.sha256()
hash_repo(pathlib.Path(sys.argv[1]), sha256)
print(sha256.hexdigest())
PY
)"

echo "STABLE_SONIC_REPO_INPUTS_DIGEST ${repo_digest}"
