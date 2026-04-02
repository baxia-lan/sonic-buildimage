#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bazel="${SONIC_BAZEL:-${repo_root}/tools/bazel/bazelw}"

build_labels=("$@")
if [[ ${#build_labels[@]} -eq 0 ]]; then
    build_labels=(//bazel/... //tools/... //sources/... //packages/... //images/... //platforms/... //installers/...)
fi

"${bazel}" --batch build --config=ci "${build_labels[@]}"

if [[ -n "${SONIC_TEST_LABELS:-}" ]]; then
    # shellcheck disable=SC2206
    test_labels=(${SONIC_TEST_LABELS})
    "${bazel}" --batch test --config=ci "${test_labels[@]}"
fi

if [[ "${SONIC_SKIP_SOURCE_CATALOG:-0}" != "1" ]]; then
    "${repo_root}/tools/ci/run_source_catalog_check.sh" "${build_labels[@]}"
fi

if [[ "${SONIC_SKIP_INSTALLER_CATALOG:-0}" != "1" ]]; then
    "${repo_root}/tools/ci/run_installer_catalog_check.sh" "${build_labels[@]}"
fi

if [[ "${SONIC_SKIP_IMAGE_METRICS:-0}" != "1" ]]; then
    "${repo_root}/tools/ci/run_image_metrics_check.sh" "${build_labels[@]}"
fi
