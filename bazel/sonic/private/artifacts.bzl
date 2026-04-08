"""Manifest-backed SONiC artifact APIs."""

load("//bazel/sonic/private:builders/deb.bzl", "sonic_deb_builder")
load("//bazel/sonic/private:builders/oci.bzl", "sonic_oci_builder")
load("//bazel/sonic/private:metadata.bzl", "COMMON_ARTIFACT_ATTRS", "SonicArtifactInfo", "write_artifact_metadata")

def _artifact_manifest_impl(ctx):
    metadata = write_artifact_metadata(ctx)
    return [
        DefaultInfo(files = depset([metadata.manifest, metadata.lock])),
        SonicArtifactInfo(
            artifact_kind = ctx.attr.artifact_kind,
            artifact_labels = metadata.transitive_labels,
            composition_depth = metadata.graph_depth,
            label = str(ctx.label),
            lock = metadata.lock,
            manifest = metadata.manifest,
        ),
    ]

_artifact_manifest = rule(
    implementation = _artifact_manifest_impl,
    attrs = COMMON_ARTIFACT_ATTRS,
    doc = "Writes a JSON manifest for a SONiC artifact migration slice.",
)

def sonic_deb_package(name, builder = None, **kwargs):
    if builder == None:
        _artifact_manifest(
            name = name,
            artifact_kind = "deb",
            **kwargs
        )
        return

    if builder == "legacy":
        fail("sonic_deb_package(builder = \"legacy\") is not implemented yet.")

    if builder == "bazel":
        if "migration_stage" not in kwargs:
            kwargs["migration_stage"] = "concrete_builder"
        sonic_deb_builder(
            name = name,
            **kwargs
        )
        return

    fail("Unsupported sonic_deb_package builder: %s" % builder)

def sonic_py_wheel(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "wheel",
        **kwargs
    )

def sonic_go_binary(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "go_binary",
        **kwargs
    )

def sonic_oci_image(name, builder = None, **kwargs):
    if builder == None:
        _artifact_manifest(
            name = name,
            artifact_kind = "oci_image",
            **kwargs
        )
        return

    if builder == "bazel":
        if "migration_stage" not in kwargs:
            kwargs["migration_stage"] = "concrete_builder"
        sonic_oci_builder(
            name = name,
            **kwargs
        )
        return

    fail("Unsupported sonic_oci_image builder: %s" % builder)

def sonic_host_image(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "host_image",
        **kwargs
    )

def sonic_platform(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "platform",
        **kwargs
    )
