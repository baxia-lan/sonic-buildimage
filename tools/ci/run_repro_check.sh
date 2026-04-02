#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
bazel="${SONIC_BAZEL:-${repo_root}/tools/bazel/bazelw}"

build_labels=("$@")
if [[ ${#build_labels[@]} -eq 0 ]]; then
    build_labels=(//bazel/... //tools/... //sources/... //packages/... //images/... //platforms/... //installers/...)
fi

tmp_root="$(mktemp -d)"
trap 'chmod -R u+w "${tmp_root}" 2>/dev/null || true; rm -rf "${tmp_root}"' EXIT

hash_output() {
    local path="$1"
    local rel="$2"

    if [[ -d "${path}" ]]; then
        while IFS= read -r file; do
            local tree_rel="${file#${path}/}"
            shasum -a 256 "${file}" | awk -v rel="${rel}/${tree_rel}" '{print rel " " $1}'
        done < <(find "${path}" -type f | sort)
        return
    fi

    shasum -a 256 "${path}" | awk -v rel="${rel}" '{print rel " " $1}'
}

collect_manifest() {
    local output_base="$1"
    shift
    local query_expr
    local files

    mkdir -p "${output_base}"
    "${bazel}" --batch --output_base="${output_base}" build --config=ci "$@" >/dev/null

    query_expr="set("
    for label in "$@"; do
        query_expr+="${label} "
    done
    query_expr+=")"

    files="$("${bazel}" --batch --output_base="${output_base}" cquery --config=ci \
        --output=files \
        "${query_expr}")"

    while IFS= read -r path; do
        [[ -z "${path}" ]] && continue
        rel="${path#${output_base}/}"
        hash_output "${path}" "${rel}"
    done <<<"${files}" | sort -u
}

manifest_one="${tmp_root}/manifest-one.txt"
manifest_two="${tmp_root}/manifest-two.txt"

collect_manifest "${tmp_root}/out-one" "${build_labels[@]}" >"${manifest_one}"
collect_manifest "${tmp_root}/out-two" "${build_labels[@]}" >"${manifest_two}"

diff -u "${manifest_one}" "${manifest_two}"
