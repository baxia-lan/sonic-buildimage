"""Shared repository helpers for non-BCR inputs."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")

def locked_http_archive(name, urls, sha256, strip_prefix = ""):
    """Declares a pinned archive dependency."""

    kwargs = {
        "name": name,
        "sha256": sha256,
        "urls": urls,
    }
    if strip_prefix:
        kwargs["strip_prefix"] = strip_prefix

    http_archive(**kwargs)

def locked_http_file(name, urls, sha256):
    """Declares a pinned file dependency."""

    http_file(
        name = name,
        sha256 = sha256,
        urls = urls,
    )
