"""Concrete SONiC Python wheel builders."""

load("//bazel/sonic/private:metadata.bzl", "COMMON_ARTIFACT_ATTRS", "SonicArtifactInfo", "write_artifact_metadata")

def _wheel_files(targets):
    files = []
    for target in targets:
        if DefaultInfo not in target:
            continue
        for file in target[DefaultInfo].files.to_list():
            if file.basename.endswith(".whl"):
                files.append(file)
    return files

def _sonic_py_wheel_builder_impl(ctx):
    metadata = write_artifact_metadata(ctx)
    wheel_output = ctx.actions.declare_file(ctx.attr.output_name)
    dependency_wheels = sorted(_wheel_files(ctx.attr.wheel_deps), key = lambda file: file.short_path)

    args = ctx.actions.args()
    args.add("--output", wheel_output.path)
    args.add("--docker-image", ctx.attr.docker_image)
    args.add("--docker-platform", ctx.attr.docker_platform)
    args.add("--source-root", ctx.attr.source_root)
    args.add("--package-name", ctx.attr.package_name)
    args.add("--version", ctx.attr.package_version)
    for dep in dependency_wheels:
        args.add("--dependency-wheel", dep.path)

    prefix = ctx.attr.source_root + "/"
    for src in sorted(ctx.files.builder_srcs, key = lambda file: file.short_path):
        if not src.short_path.startswith(prefix):
            fail("%s is outside declared source_root %s" % (src.short_path, ctx.attr.source_root))
        args.add("--src-map", "%s=%s" % (src.path, src.short_path[len(prefix):]))

    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = depset(ctx.files.builder_srcs + dependency_wheels),
        outputs = [wheel_output],
        arguments = [args],
        tools = [ctx.executable._builder],
        mnemonic = "SonicPyWheel",
        progress_message = "Building SONiC Python wheel %s" % ctx.label,
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
    )

    return [
        DefaultInfo(files = depset([wheel_output, metadata.manifest, metadata.lock])),
        SonicArtifactInfo(
            artifact_kind = ctx.attr.artifact_kind,
            artifact_labels = metadata.transitive_labels,
            composition_depth = metadata.graph_depth,
            label = str(ctx.label),
            lock = metadata.lock,
            manifest = metadata.manifest,
        ),
    ]

_sonic_py_wheel_builder = rule(
    implementation = _sonic_py_wheel_builder_impl,
    attrs = dict(
        COMMON_ARTIFACT_ATTRS,
        builder_srcs = attr.label_list(
            allow_files = True,
            mandatory = True,
        ),
        source_root = attr.string(mandatory = True),
        output_name = attr.string(mandatory = True),
        package_name = attr.string(mandatory = True),
        package_version = attr.string(mandatory = True),
        docker_image = attr.string(),
        docker_platform = attr.string(default = "linux/amd64"),
        _builder = attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:build_wheel_package"),
        ),
    ),
    doc = "Builds a real SONiC Python wheel while preserving artifact metadata side outputs.",
)

def sonic_py_wheel_builder(name, **kwargs):
    _sonic_py_wheel_builder(
        name = name,
        artifact_kind = "wheel",
        **kwargs
    )
