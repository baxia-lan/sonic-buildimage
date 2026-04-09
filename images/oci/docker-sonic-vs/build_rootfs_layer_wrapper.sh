#!/usr/bin/env bash
set -euo pipefail

exec bash tools/bazel/build_rootfs_layer.sh "$@"
