#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

artifact="bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz"
target_artifact="bazel-bin/images/oci/docker-sonic-vs/target_tree/target/docker-sonic-vs.gz"

echo "== Branch =="
git rev-parse --short HEAD
git log --oneline -n 5

echo
echo "== Build =="
./tools/bazel/bazelw --batch build --config=ci \
  //images/oci/docker-sonic-vs:image \
  //images/oci/docker-sonic-vs:target_tree

echo
echo "== Artifacts =="
ls -lh "$artifact" "$target_artifact"

echo
echo "== Integrity =="
gzip -t "$artifact"
shasum -a 256 "$artifact"

echo
echo "== Docker Load =="
docker load -i "$artifact"

echo
echo "== Non-Hermetic Audit Summary =="
python3 tools/ci/collect_nonhermetic_deps.py --format json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["summary"])'
