"""Internal helpers for OCI layer assembly."""

load("//bazel/sonic/private:artifacts.bzl", "DEFAULT_CONCRETE_BUILDER_IMAGE")

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

def _layer_files(targets):
    files = []
    for target in targets:
        if DefaultInfo not in target:
            continue
        for file in target[DefaultInfo].files.to_list():
            if file.basename.endswith(".tar") or file.basename.endswith(".tar.gz") or file.basename.endswith(".tgz"):
                files.append(file)
    return files

def _sonic_rootfs_layer_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.output_name)
    runtime_debs = sorted(_deb_files(ctx.attr.runtime_deps), key = lambda file: file.short_path)
    runtime_layers = sorted(_layer_files(ctx.attr.runtime_layers), key = lambda file: file.short_path)
    wheel_files = sorted(_wheel_files(ctx.attr.wheel_deps), key = lambda file: file.short_path)
    static_files = sorted(ctx.files.files, key = lambda file: file.short_path)
    static_files_by_path = {file.short_path: file for file in static_files}

    args = ctx.actions.args()
    args.add("--output", output.path)
    args.add("--docker-image", ctx.attr.docker_image)
    args.add("--docker-platform", ctx.attr.docker_platform)
    for deb in runtime_debs:
        args.add("--runtime-deb", deb.path)
    for layer in runtime_layers:
        args.add("--runtime-layer", layer.path)
    for wheel in wheel_files:
        args.add("--wheel", wheel.path)
    for mapping in ctx.attr.file_maps:
        if "=" not in mapping:
            fail("Invalid file_maps entry %r; expected <short_path>=<dest>" % mapping)
        src_path, dest = mapping.split("=", 1)
        if src_path not in static_files_by_path:
            fail("file_maps references %s but it is not present in files" % src_path)
        args.add("--file-map", "%s=%s" % (static_files_by_path[src_path].path, dest))

    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = depset(static_files + runtime_debs + runtime_layers + wheel_files),
        outputs = [output],
        arguments = [args],
        tools = [ctx.executable._builder],
        mnemonic = "SonicRootfsLayer",
        progress_message = "Building SONiC OCI layer %s" % ctx.label,
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
    )

    return [DefaultInfo(files = depset([output]))]

_sonic_rootfs_layer = rule(
    implementation = _sonic_rootfs_layer_impl,
    attrs = {
        "docker_image": attr.string(default = DEFAULT_CONCRETE_BUILDER_IMAGE),
        "docker_platform": attr.string(default = "linux/amd64"),
        "runtime_deps": attr.label_list(),
        "runtime_layers": attr.label_list(allow_files = True),
        "wheel_deps": attr.label_list(),
        "files": attr.label_list(allow_files = True),
        "file_maps": attr.string_list(),
        "output_name": attr.string(mandatory = True),
        "_builder": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:build_rootfs_layer"),
        ),
    },
    doc = "Builds a deterministic OCI layer tar from Debian packages, Python wheels, and mapped repo files.",
)

def sonic_rootfs_layer(name, **kwargs):
    _sonic_rootfs_layer(name = name, **kwargs)
