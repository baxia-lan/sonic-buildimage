#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: export_target_tree.sh <output-dir> <src>=<dest> [<src>=<dest> ...]

Copies Bazel-produced files into a legacy target tree layout.
EOF
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

output_dir="$1"
shift

mkdir -p "${output_dir}"

for mapping in "$@"; do
    src="${mapping%%=*}"
    dest="${mapping#*=}"

    if [[ -z "${src}" || -z "${dest}" || "${src}" == "${dest}" ]]; then
        echo "Invalid export mapping: ${mapping}" >&2
        exit 1
    fi

    if [[ ! -f "${src}" ]]; then
        echo "Export source does not exist: ${src}" >&2
        exit 1
    fi

    mkdir -p "$(dirname "${output_dir}/${dest}")"
    install "${src}" "${output_dir}/${dest}"
done
