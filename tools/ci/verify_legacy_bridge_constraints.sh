#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

bridge_script="tools/bazel/build_legacy_artifact_bridge.sh"
bridge_rule="bazel/sonic/private/bridge.bzl"
status_script="tools/bazel/workspace_status.sh"
bazelrc_file=".bazelrc"

for path in "${bridge_script}" "${bridge_rule}" "${status_script}" "${bazelrc_file}"; do
    if [[ ! -f "${path}" ]]; then
        echo "Missing required legacy bridge file: ${path}" >&2
        exit 1
    fi
done

if rg -n \
    '(apt-get|pip3?[[:space:]]+install|curl[[:space:]]|wget[[:space:]]|docker[[:space:]]+build)' \
    "${bridge_script}"; then
    echo "Legacy bridge action script must not fetch from the network or install packages at execution time." >&2
    exit 1
fi

if ! rg -q --fixed-strings 'common --workspace_status_command=./tools/bazel/workspace_status.sh' "${bazelrc_file}"; then
    echo "Bazel must configure workspace_status_command for the legacy bridge repo digest." >&2
    exit 1
fi

if ! rg -q --fixed-strings 'STABLE_SONIC_REPO_INPUTS_DIGEST' "${status_script}"; then
    echo "Workspace status script must emit STABLE_SONIC_REPO_INPUTS_DIGEST." >&2
    exit 1
fi

if ! rg -q --fixed-strings 'ctx.info_file.path' "${bridge_rule}"; then
    echo "Legacy bridge rule must consume ctx.info_file for stable workspace status." >&2
    exit 1
fi

if ! rg -q --fixed-strings 'args.add("--version-file", ctx.info_file.path)' "${bridge_rule}"; then
    echo "Legacy bridge rule must pass the stable status file to the bridge helper." >&2
    exit 1
fi

if ! rg -q --fixed-strings 'source_fingerprint="$(awk '\''/^STABLE_SONIC_REPO_INPUTS_DIGEST / { print $2; exit }'\'' "${version_file}")"' "${bridge_script}"; then
    echo "Legacy bridge script must derive its source fingerprint from STABLE_SONIC_REPO_INPUTS_DIGEST." >&2
    exit 1
fi

echo "Legacy bridge hermeticity constraints verified."
