#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

required_files=(
    MODULE.bazel
    MODULE.bazel.lock
    AGENTS.md
)

for path in "${required_files[@]}"; do
    if [[ ! -f "${path}" ]]; then
        echo "Missing required Bazel migration file: ${path}" >&2
        exit 1
    fi
done

scan_roots=()
for path in bazel packages images installers; do
    if [[ -d "${path}" ]]; then
        scan_roots+=("${path}")
    fi
done

if [[ ${#scan_roots[@]} -eq 0 ]]; then
    echo "No Bazel artifact directories found to scan; checking bazel/ only is sufficient for now."
    scan_roots=(bazel)
fi

if rg -n --glob '!**/README*' --glob '!**/*.md' \
    '(apt-get|pip3?[[:space:]]+install|curl[[:space:]]|wget[[:space:]])' \
    "${scan_roots[@]}"; then
    echo "Detected non-hermetic network/package-install commands in Bazel-managed paths." >&2
    exit 1
fi
