#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  bazel run //tools/bazel:init_workspace
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

workspace_root="${BUILD_WORKSPACE_DIRECTORY:-}"
if [[ -z "${workspace_root}" ]]; then
    echo "init_workspace.sh must be run via 'bazel run'" >&2
    exit 1
fi

cd "${workspace_root}"

if [[ ! -f .gitmodules ]]; then
    echo "No .gitmodules found in ${workspace_root}" >&2
    exit 0
fi

git submodule update --init --recursive

git submodule foreach --recursive '
if [ -f .git ]; then
    gitdir_path="$(cut -d" " -f2 .git)"
    relative_gitdir="$(python3 -c '"'"'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), sys.argv[2]))'"'"' "${gitdir_path}" "$(pwd)")"
    printf "gitdir: %s\n" "${relative_gitdir}" > .git
fi
'

echo "Initialized git submodules under ${workspace_root}"
