#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

out_dir="${repo_root}/out/bazel-migration/presubmit"
mkdir -p "${out_dir}"

summary="${out_dir}/summary.txt"
labels="${SONIC_AFFECTED_LABELS:-//bazel/... //tools/... //sources/... //packages/... //images/... //platforms/... //installers/...}"
current_step=""
last_log=""

{
    echo "build_id=${BUILD_ID:-unknown}"
    echo "branch=${BRANCH_NAME:-unknown}"
    echo "commit=${COMMIT_SHA:-unknown}"
    echo "labels=${labels}"
} > "${summary}"

finalize() {
    local exit_code="$?"

    if [[ "${exit_code}" -eq 0 ]]; then
        echo "status=success" >> "${summary}"
    else
        echo "status=failure" >> "${summary}"
        if [[ -n "${current_step}" ]]; then
            echo "failed_step=${current_step}" >> "${summary}"
        fi
        if [[ -n "${last_log}" ]]; then
            echo "failed_log=${last_log}" >> "${summary}"
        fi
        echo "exit_code=${exit_code}" >> "${summary}"
    fi

    echo "summary_file=${summary}" >> "${summary}"
    echo "== presubmit summary =="
    cat "${summary}"

    exit "${exit_code}"
}
trap finalize EXIT

run_logged() {
    local name="$1"
    shift
    local logfile="${out_dir}/${name}.log"
    local start_ts
    local end_ts

    current_step="${name}"
    last_log="${logfile}"
    echo "== ${name} =="
    start_ts="$(date +%s)"
    "$@" 2>&1 | tee "${logfile}"
    end_ts="$(date +%s)"
    echo "step.${name}.status=success" >> "${summary}"
    echo "step.${name}.seconds=$((end_ts - start_ts))" >> "${summary}"
    current_step=""
}

run_logged git-submodules git submodule update --init --recursive
run_logged artifact-inventory ./tools/ci/collect_artifact_inventory.py --out-dir "${out_dir}/inventory"
run_logged affected-targets ./tools/ci/run_affected_targets.sh ${labels}
run_logged no-egress ./tools/ci/verify_no_egress.sh
