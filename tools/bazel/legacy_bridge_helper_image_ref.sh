#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
declare -a helper_inputs=(
    "tools/bazel/legacy_bridge_helper.Dockerfile"
    "tools/bazel/legacy_bridge_helper.apt.txt"
    "tools/bazel/legacy_bridge_helper.requirements.txt"
)

for input in "${helper_inputs[@]}"; do
    if [[ ! -f "${workspace_root}/${input}" ]]; then
        echo "missing legacy bridge helper input: ${input}" >&2
        exit 1
    fi
done

helper_digest="$(
    {
        for input in "${helper_inputs[@]}"; do
            printf '%s\0' "${input}"
            shasum -a 256 "${workspace_root}/${input}"
        done
    } | shasum -a 256 | awk '{print $1}'
)"

printf 'sonic-bazel-legacy-bridge-helper:bookworm-%s\n' "${helper_digest:0:16}"
