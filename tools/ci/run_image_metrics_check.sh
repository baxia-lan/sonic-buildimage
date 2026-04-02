#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
labels=("$@")

if [[ ${#labels[@]} -eq 0 ]]; then
    labels=(//sources/... //packages/... //images/...)
fi

"${repo_root}/tools/ci/collect_image_metrics.py" \
    --out-dir out/bazel-migration/image-metrics \
    --budget-file tools/ci/image_budgets.json \
    "${labels[@]}"
