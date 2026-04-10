#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

out_dir="${repo_root}/out/bazel-migration/presubmit"
mkdir -p "${out_dir}"

summary="${out_dir}/summary.txt"
labels="${SONIC_AFFECTED_LABELS:-//bazel/... //tools/... //sources/... //packages/... //images/... //platforms/... //installers/...}"

{
    echo "build_id=${BUILD_ID:-unknown}"
    echo "branch=${BRANCH_NAME:-unknown}"
    echo "commit=${COMMIT_SHA:-unknown}"
    echo "labels=${labels}"
} > "${summary}"

run_logged() {
    local name="$1"
    shift
    local logfile="${out_dir}/${name}.log"

    echo "== ${name} =="
    "$@" 2>&1 | tee "${logfile}"
}

run_logged git-submodules git submodule update --init --recursive
run_logged artifact-inventory ./tools/ci/collect_artifact_inventory.py --out-dir "${out_dir}/inventory"
run_logged affected-targets ./tools/ci/run_affected_targets.sh ${labels}
run_logged no-egress ./tools/ci/verify_no_egress.sh

echo "status=success" >> "${summary}"
