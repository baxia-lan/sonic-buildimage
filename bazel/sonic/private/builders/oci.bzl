"""Concrete SONiC OCI image builders."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")
load("//bazel/sonic/private:metadata.bzl", "COMMON_ARTIFACT_ATTRS", "SonicArtifactInfo", "write_artifact_metadata")

def _deb_files(targets):
    files = []
    for target in targets:
        if DefaultInfo not in target:
            continue
        for file in target[DefaultInfo].files.to_list():
            if file.basename.endswith(".deb"):
                files.append(file)
    return files

def _wheel_files(targets):
    files = []
    for target in targets:
        if DefaultInfo not in target:
            continue
        for file in target[DefaultInfo].files.to_list():
            if file.basename.endswith(".whl"):
                files.append(file)
    return files

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

def _sonic_local_docker_archive_impl(ctx):
    metadata = write_artifact_metadata(ctx)
    image_output = ctx.actions.declare_file(ctx.attr.output_name)
    runtime_debs = sorted(_deb_files(ctx.attr.runtime_deps), key = lambda file: file.short_path)
    wheel_files = sorted(_wheel_files(ctx.attr.wheel_deps), key = lambda file: file.short_path)
    static_files = sorted(ctx.files.builder_files, key = lambda file: file.short_path)
    static_files_by_path = {file.short_path: file for file in static_files}

    args = ctx.actions.args()
    args.add("--output", image_output.path)
    args.add("--base-image", ctx.attr.builder_rootfs_base_image)
    args.add("--builder-image", ctx.attr.builder_docker_image if ctx.attr.builder_docker_image else ctx.attr.builder_rootfs_base_image)
    args.add("--docker-platform", ctx.attr.docker_platform)
    args.add("--env-json", json.encode(dict(sorted(ctx.attr.builder_env.items()))))
    if ctx.attr.builder_entrypoint:
        args.add("--entrypoint-json", json.encode(ctx.attr.builder_entrypoint))
    if ctx.attr.builder_cmd:
        args.add("--cmd-json", json.encode(ctx.attr.builder_cmd))
    if ctx.attr.builder_user:
        args.add("--user", ctx.attr.builder_user)
    if ctx.attr.builder_workdir:
        args.add("--workdir", ctx.attr.builder_workdir)
    for tag in ctx.attr.builder_repo_tags:
        args.add("--repo-tag", tag)
    for deb in runtime_debs:
        args.add("--runtime-deb", deb.path)
    for wheel in wheel_files:
        args.add("--wheel", wheel.path)
    for mapping in ctx.attr.builder_file_maps:
        if "=" not in mapping:
            fail("Invalid builder_file_maps entry %r; expected <short_path>=<dest>" % mapping)
        src_path, dest = mapping.split("=", 1)
        if src_path not in static_files_by_path:
            fail("builder_file_maps references %s but it is not present in builder_files" % src_path)
        args.add("--file-map", "%s=%s" % (static_files_by_path[src_path].path, dest))

    ctx.actions.run(
        executable = ctx.executable._local_archive_builder,
        inputs = depset(static_files + runtime_debs + wheel_files),
        outputs = [image_output],
        arguments = [args],
        tools = [ctx.executable._local_archive_builder],
        mnemonic = "SonicDockerArchive",
        progress_message = "Building SONiC Docker archive %s" % ctx.label,
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
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

_sonic_local_docker_archive = rule(
    implementation = _sonic_local_docker_archive_impl,
    attrs = dict(
        COMMON_ARTIFACT_ATTRS,
        output_name = attr.string(mandatory = True),
        builder_rootfs_base_image = attr.string(mandatory = True),
        builder_docker_image = attr.string(),
        docker_platform = attr.string(default = "linux/amd64"),
        builder_repo_tags = attr.string_list(),
        builder_cmd = attr.string_list(),
        builder_entrypoint = attr.string_list(),
        builder_env = attr.string_dict(),
        builder_files = attr.label_list(allow_files = True),
        builder_file_maps = attr.string_list(),
        builder_user = attr.string(),
        builder_workdir = attr.string(),
        _local_archive_builder = attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:build_docker_archive"),
        ),
    ),
)

def sonic_oci_builder(
        name,
        *,
        builder_base = None,
        builder_cmd = None,
        builder_entrypoint = None,
        builder_env = None,
        builder_files = None,
        builder_file_maps = None,
        builder_docker_image = None,
        builder_repo_tags = None,
        builder_rootfs_base_image = None,
        builder_tars = None,
        builder_user = None,
        builder_workdir = None,
        image_format = "docker",
        output_name,
        **kwargs):
    if builder_rootfs_base_image != None:
        if builder_repo_tags == None:
            builder_repo_tags = [name + ":latest"]
        if builder_env == None:
            builder_env = {}
        if builder_files == None:
            builder_files = []
        if builder_file_maps == None:
            builder_file_maps = []

        _sonic_local_docker_archive(
            name = name,
            artifact_kind = "oci_image",
            builder_cmd = builder_cmd,
            builder_docker_image = builder_docker_image,
            builder_entrypoint = builder_entrypoint,
            builder_env = builder_env,
            builder_files = builder_files,
            builder_file_maps = builder_file_maps,
            builder_repo_tags = builder_repo_tags,
            builder_rootfs_base_image = builder_rootfs_base_image,
            builder_user = builder_user,
            builder_workdir = builder_workdir,
            docker_platform = kwargs.pop("docker_platform", "linux/amd64"),
            output_name = output_name,
            **kwargs
        )
        return

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
