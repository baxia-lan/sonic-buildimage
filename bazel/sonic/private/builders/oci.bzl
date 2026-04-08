"""Concrete SONiC OCI image builders."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")
load("//bazel/sonic/private:metadata.bzl", "COMMON_ARTIFACT_ATTRS", "SonicArtifactInfo", "write_artifact_metadata")

def _sonic_oci_builder_impl(ctx):
    metadata = write_artifact_metadata(ctx)
    image_output = ctx.actions.declare_file(ctx.attr.output_name)

    args = ctx.actions.args()
    args.add("--input", ctx.file.image_tarball.path)
    args.add("--output", image_output.path)

    ctx.actions.run(
        executable = ctx.executable._gzip_tool,
        inputs = [ctx.file.image_tarball],
        outputs = [image_output],
        arguments = [args],
        tools = [ctx.executable._gzip_tool],
        mnemonic = "SonicOciArchive",
        progress_message = "Packaging SONiC OCI archive %s" % ctx.label,
    )

    return [
        DefaultInfo(files = depset([image_output, metadata.manifest, metadata.lock])),
        SonicArtifactInfo(
            artifact_kind = ctx.attr.artifact_kind,
            artifact_labels = metadata.transitive_labels,
            composition_depth = metadata.graph_depth,
            label = str(ctx.label),
            lock = metadata.lock,
            manifest = metadata.manifest,
        ),
    ]

_sonic_oci_builder = rule(
    implementation = _sonic_oci_builder_impl,
    attrs = dict(
        COMMON_ARTIFACT_ATTRS,
        image_tarball = attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        output_name = attr.string(mandatory = True),
        _gzip_tool = attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:gzip_file"),
        ),
    ),
    doc = "Packages a Bazel-native OCI tarball as the canonical SONiC image artifact while preserving metadata side outputs.",
)

def sonic_oci_builder(
        name,
        *,
        builder_base = None,
        builder_cmd = None,
        builder_entrypoint = None,
        builder_env = None,
        builder_repo_tags = None,
        builder_tars = None,
        builder_user = None,
        builder_workdir = None,
        image_format = "docker",
        output_name,
        **kwargs):
    if builder_tars == None:
        builder_tars = []
    if builder_repo_tags == None:
        builder_repo_tags = [name + ":latest"]
    if builder_env == None:
        builder_env = {}

    oci_image_name = name + "__oci"
    oci_load_name = name + "__load"
    tarball_name = name + "__tarball"

    oci_image(
        name = oci_image_name,
        base = builder_base,
        cmd = builder_cmd,
        entrypoint = builder_entrypoint,
        env = builder_env,
        tars = builder_tars,
        user = builder_user,
        workdir = builder_workdir,
    )

    oci_load(
        name = oci_load_name,
        format = image_format,
        image = ":" + oci_image_name,
        repo_tags = builder_repo_tags,
    )

    native.filegroup(
        name = tarball_name,
        srcs = [":" + oci_load_name],
        output_group = "tarball",
    )

    _sonic_oci_builder(
        name = name,
        artifact_kind = "oci_image",
        image_tarball = ":" + tarball_name,
        output_name = output_name,
        **kwargs
    )
