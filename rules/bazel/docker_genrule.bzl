"""Genrule wrapper that executes commands inside a Docker container.

On Linux (CI/RBE), commands run natively for performance.
On macOS (dev), commands run inside a Debian container via `docker run`.

This enables the same BUILD files to work on both platforms without
modification — the developer experience matches CI behavior.
"""

_DEBIAN_IMAGE = "debian:bookworm-slim@sha256:4724b8cc51e33e398f0e2e15e18d5ec2851ff0c2280647e1310bc1642182655d"

def docker_genrule(
        name,
        srcs = [],
        outs = [],
        docker_cmd = "",
        docker_image = _DEBIAN_IMAGE,
        extra_packages = [],
        tags = [],
        visibility = None):
    """A genrule that runs its command inside a Docker container.

    Args:
        name:           Target name.
        srcs:           Input file labels.
        outs:           Output file names (basenames).
        docker_cmd:     Shell script to run inside the container.
                        Available variables: ROOTFS (temp dir for output),
                        OUT_DIR (where to write final output files).
        docker_image:   Docker image to use (default: debian:bookworm-slim).
        extra_packages: Extra apt packages to install before running docker_cmd.
        tags:           Bazel tags.
        visibility:     Bazel visibility.
    """
    apt_install = ""
    if extra_packages:
        apt_install = "apt-get update -qq && apt-get install -y -qq --no-install-recommends %s && " % " ".join(extra_packages)

    native.genrule(
        name = name,
        srcs = srcs,
        outs = outs,
        cmd = """
set -euo pipefail
OUT_DIR=$$(cd $$(dirname $(OUTS)) && pwd)

if command -v apt-get >/dev/null 2>&1; then
    # Running on Linux — execute directly
    {apt_install}
    ROOTFS=$$(mktemp -d)
    trap 'rm -rf "$$ROOTFS"' EXIT
    export ROOTFS OUT_DIR
    {docker_cmd}
else
    # Running on macOS — use Docker
    WORK=$$(mktemp -d)
    trap 'rm -rf "$$WORK"' EXIT

    # Copy input files into a staging dir for Docker mount
    for src in $(SRCS); do
        cp "$$src" "$$WORK/" 2>/dev/null || true
    done

    docker run --rm \\
        -v "$$WORK:/work" \\
        -v "$$OUT_DIR:/output" \\
        -e DEBIAN_FRONTEND=noninteractive \\
        -e SOURCE_DATE_EPOCH=0 \\
        -w /work \\
        {docker_image} \\
        bash -euo pipefail -c '
            {apt_install}
            ROOTFS=$$(mktemp -d)
            export ROOTFS
            export OUT_DIR=/output
            {docker_cmd}
        '
fi
""".format(
            docker_cmd = docker_cmd,
            docker_image = docker_image,
            apt_install = apt_install,
        ),
        tags = tags + ["requires-docker"],
        visibility = visibility,
    )
