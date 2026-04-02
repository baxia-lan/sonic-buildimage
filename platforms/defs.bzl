"""Shared macros for SONiC platform migration targets."""

load("//bazel/sonic:defs.bzl", "sonic_platform")

def sonic_platform_manifest(name, data):
    sonic_platform(
        name = name,
        **dict(data)
    )
