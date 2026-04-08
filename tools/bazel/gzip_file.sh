#!/usr/bin/env bash
set -euo pipefail

input=""
output=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            input="$2"
            shift 2
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${input}" || -z "${output}" ]]; then
    echo "--input and --output are required" >&2
    exit 1
fi

python3 - "$input" "$output" <<'PY'
import gzip
import shutil
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
with open(src_path, "rb") as src:
    with open(out_path, "wb") as out:
        with gzip.GzipFile(filename="", mode="wb", mtime=0, fileobj=out) as dst:
            shutil.copyfileobj(src, dst)
PY
