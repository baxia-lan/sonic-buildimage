#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
image_ref_script="${workspace_root}/tools/bazel/legacy_bridge_helper_image_ref.sh"
image_tag="${SONIC_BAZEL_LEGACY_BRIDGE_HELPER_IMAGE:-$("${image_ref_script}")}"
stable_tag="sonic-bazel-legacy-bridge-helper:bookworm"
dockerfile="${workspace_root}/tools/bazel/legacy_bridge_helper.Dockerfile"
context_dir="$(mktemp -d)"

cleanup() {
    rm -rf "${context_dir}"
}
trap cleanup EXIT

mkdir -p "${context_dir}/tools/bazel"
cp "${dockerfile}" "${context_dir}/tools/bazel/legacy_bridge_helper.Dockerfile"
cp "${workspace_root}/tools/bazel/legacy_bridge_helper.apt.txt" "${context_dir}/tools/bazel/legacy_bridge_helper.apt.txt"
cp "${workspace_root}/tools/bazel/legacy_bridge_helper.requirements.txt" "${context_dir}/tools/bazel/legacy_bridge_helper.requirements.txt"

set -x
"${docker_bin}" build \
    --platform "${DOCKER_DEFAULT_PLATFORM:-linux/amd64}" \
    -f "${context_dir}/tools/bazel/legacy_bridge_helper.Dockerfile" \
    -t "${image_tag}" \
    "${context_dir}"

if [[ "${image_tag}" != "${stable_tag}" ]]; then
    "${docker_bin}" tag "${image_tag}" "${stable_tag}"
fi
