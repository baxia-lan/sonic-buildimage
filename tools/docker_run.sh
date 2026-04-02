#!/usr/bin/env bash
# Wrapper to run a build command inside a Debian container on macOS.
# On Linux, runs the command directly. Used by Bazel genrules.
#
# Usage: docker_run.sh <output_dir> <script>
# The script receives ROOTFS and OUT_DIR environment variables.
set -euo pipefail

OUT_DIR="$1"
shift
SCRIPT="$1"
shift

DOCKER_IMAGE="${DOCKER_IMAGE:-debian:bookworm-slim}"

if [[ "$(uname)" == "Linux" ]]; then
    # On Linux, run directly
    export ROOTFS=$(mktemp -d)
    trap 'rm -rf "$ROOTFS"' EXIT
    export OUT_DIR
    bash -euo pipefail -c "$SCRIPT"
else
    # On macOS, run inside Docker
    # Mount the output directory for writing results
    mkdir -p "$OUT_DIR"
    docker run --rm \
        -v "$OUT_DIR:/output" \
        -e DEBIAN_FRONTEND=noninteractive \
        "$DOCKER_IMAGE" \
        bash -euo pipefail -c "$SCRIPT"
fi
