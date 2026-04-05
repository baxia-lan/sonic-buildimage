#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
docker_bin="${DOCKER_BIN:-docker}"
image_tag="${SONIC_BAZEL_LEGACY_BRIDGE_HELPER_IMAGE:-sonic-bazel-legacy-bridge-helper:bookworm}"
dockerfile="${workspace_root}/tools/bazel/legacy_bridge_helper.Dockerfile"

exec "${docker_bin}" build \
    --platform "${DOCKER_DEFAULT_PLATFORM:-linux/amd64}" \
    -f "${dockerfile}" \
    -t "${image_tag}" \
    "${workspace_root}"
