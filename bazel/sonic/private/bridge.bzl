"""Private concrete bridge rules for legacy SONiC artifact builders."""

def _legacy_artifact_bridge_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.output_name)
    manifest_files = []
    if ctx.attr.manifest:
        manifest_files = ctx.attr.manifest[DefaultInfo].files.to_list()

    args = ctx.actions.args()
    args.add("--workspace-marker", ctx.file.workspace_marker.path)
    args.add("--version-file", ctx.info_file.path)
    args.add("--output", output.path)
    args.add("--legacy-target", ctx.attr.legacy_target)
    args.add("--artifact-path", ctx.attr.artifact_path)
    args.add("--platform", ctx.attr.platform)
    args.add("--bldenv", ctx.attr.bldenv)
    args.add("--docker-platform", ctx.attr.docker_platform)

    for manifest_file in manifest_files:
        if manifest_file.basename.endswith(".manifest.json"):
            args.add("--manifest", manifest_file.path)
            break

    for make_var in ctx.attr.make_vars:
        args.add("--make-var", make_var)

    inputs = [ctx.file.workspace_marker, ctx.info_file]
    inputs.extend(manifest_files)

    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = depset(inputs),
        outputs = [output],
        arguments = [args],
        tools = [ctx.executable._builder],
        env = {
            "SONIC_BAZEL_LEGACY_BRIDGE_CACHE_GEN": ctx.attr.bridge_cache_generation,
        },
        mnemonic = "SonicLegacyArtifactBridge",
        progress_message = "Building legacy SONiC artifact %s via Bazel bridge" % ctx.label,
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
            "no-cache": "1",
        },
    )

    return [DefaultInfo(files = depset([output]))]

_legacy_artifact_bridge = rule(
    implementation = _legacy_artifact_bridge_impl,
    attrs = {
        "artifact_path": attr.string(mandatory = True),
        "bldenv": attr.string(default = "bookworm"),
        "bridge_cache_generation": attr.string(default = "v8"),
        "docker_platform": attr.string(mandatory = True),
        "legacy_target": attr.string(mandatory = True),
        "make_vars": attr.string_list(),
        "manifest": attr.label(
            allow_files = True,
        ),
        "output_name": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
        "workspace_marker": attr.label(
            allow_single_file = True,
            default = Label("//:workspace_marker"),
        ),
        "_builder": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:build_legacy_artifact_bridge"),
        ),
    },
    doc = "Runs a local no-sandbox bridge that delegates a Bazel target to a legacy concrete SONiC build.",
)

def legacy_artifact_bridge(name, **kwargs):
    _legacy_artifact_bridge(
        name = name,
        **kwargs
    )
