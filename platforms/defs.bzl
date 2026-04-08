"""Shared macros for SONiC platform migration targets."""

load("//bazel/sonic:defs.bzl", "sonic_platform")

def sonic_platform_manifest(name, data):
    sonic_platform(
        name = name,
        **dict(data)
    )

def sonic_platform_prepare_targets(data):
    configured_arches = data.get("configured_arches", [])
    if len(configured_arches) != 1:
        fail("sonic_platform_prepare_targets currently requires exactly one configured arch, got %s" % configured_arches)

    native.sh_binary(
        name = "configure",
        srcs = ["//tools/bazel:configure_platform.sh"],
        args = [
            "--platform",
            data["platform_name"],
            "--arch",
            configured_arches[0],
        ],
    )

    native.sh_binary(
        name = "prepare",
        srcs = ["//tools/bazel:configure_platform.sh"],
        args = [
            "--init-workspace",
            "--platform",
            data["platform_name"],
            "--arch",
            configured_arches[0],
        ],
    )
