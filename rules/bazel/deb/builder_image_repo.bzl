"""Hermetic builder Docker image — pre-installs all build deps at fetch time.

Creates a Docker image with all build dependencies pre-installed from
snapshot.debian.org. The image is saved as a tar and loaded at build time.
Build actions use this image directly — zero apt-get, zero network.

This solves the hermeticity violation where deb_package_set genrules
run apt-get install during build actions.

Usage in MODULE.bazel:
    _builder_image = use_repo_rule(
        "//rules/bazel/deb:builder_image_repo.bzl", "sonic_builder_image_repo")
    _builder_image(
        name = "sonic_builder",
        base_image = "debian:bookworm-slim@sha256:...",
        apt_snapshot = "https://snapshot.debian.org/archive/debian/20260401T000000Z",
        packages = ["build-essential", "dpkg-dev", ...],
    )
"""

def _sonic_builder_image_repo_impl(rctx):
    base = rctx.attr.base_image
    snapshot = rctx.attr.apt_snapshot
    pkgs = " ".join(rctx.attr.packages)

    # Build the Docker image at fetch time
    dockerfile = """\
FROM {base}
RUN echo "deb {snapshot} bookworm main" > /etc/apt/sources.list && \\
    echo "deb {snapshot_sec} bookworm-security main" >> /etc/apt/sources.list && \\
    apt-get update -qq && \\
    apt-get install -y -qq --no-install-recommends {packages} && \\
    rm -rf /var/lib/apt/lists/* && \\
    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq.hpp -o /usr/include/zmq.hpp && \\
    curl -sSL https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq_addon.hpp -o /usr/include/zmq_addon.hpp && \\
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal 2>/dev/null
ENV PATH="/root/.cargo/bin:${{PATH}}"
""".format(
        base = base,
        snapshot = snapshot,
        snapshot_sec = snapshot.replace("/archive/debian/", "/archive/debian-security/"),
        packages = pkgs,
    )

    rctx.file("Dockerfile", dockerfile)

    # Build the image
    tag = "sonic-builder:local"
    result = rctx.execute(["docker", "build", "--platform", "linux/amd64",
                            "-t", tag, "-f", "Dockerfile", "."])
    if result.return_code != 0:
        fail("Failed to build sonic-builder image: " + result.stderr)

    # Save the image digest
    inspect = rctx.execute(["docker", "inspect", "--format", "{{.Id}}", tag])
    if inspect.return_code != 0:
        fail("Failed to inspect builder image: " + inspect.stderr)
    image_id = inspect.stdout.strip()

    rctx.file("image_id.txt", image_id)
    rctx.file("image_tag.txt", tag)

    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["image_id.txt", "image_tag.txt"])
""")

sonic_builder_image_repo = repository_rule(
    implementation = _sonic_builder_image_repo_impl,
    attrs = {
        "base_image": attr.string(
            mandatory = True,
            doc = "Base Docker image with sha256 digest.",
        ),
        "apt_snapshot": attr.string(
            mandatory = True,
            doc = "Snapshot URL for deterministic apt installs.",
        ),
        "packages": attr.string_list(
            mandatory = True,
            doc = "List of apt packages to pre-install.",
        ),
    },
    doc = "Builds a Docker image with all build deps at fetch time (hermetic).",
)
