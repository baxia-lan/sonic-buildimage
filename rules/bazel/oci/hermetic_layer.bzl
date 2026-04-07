"""Hermetic OCI layer assembly using rules_distroless packages.

No Docker, no apt-get at build time. All packages resolved at fetch time
via rules_distroless from snapshot.debian.org.

Usage:
    deb_layer(
        name = "redis_layer",
        debs = [
            "@bookworm_redis-server_5-7.0.15-1_deb12u6_amd64//:data",
            "@bookworm_redis-tools_5-7.0.15-1_deb12u6_amd64//:data",
        ],
    )
"""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def deb_layer(name, debs, visibility = None):
    """Create an OCI layer from pre-resolved Debian packages.

    Each deb is a rules_distroless package repo that exposes :data (the .deb content).
    This macro extracts and merges them into a single layer tar.

    Args:
        name:  Target name. Produces <name>.tar
        debs:  List of labels pointing to rules_distroless package data.
        visibility: Bazel visibility.
    """
    pkg_tar(
        name = name,
        srcs = debs,
        package_dir = "/",
        visibility = visibility,
    )
