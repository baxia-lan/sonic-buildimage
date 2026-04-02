"""Export APIs for materializing Bazel outputs into the legacy target/ tree."""

def _normalize_export_path(path):
    if not path:
        fail("Export destination must not be empty.")
    if path.startswith("/"):
        fail("Export destination %r must be relative." % path)
    segments = path.split("/")
    if "." in segments or ".." in segments:
        fail("Export destination %r must not contain '.' or '..' segments." % path)
    return path

def _sonic_export_to_target_tree_impl(ctx):
    output_dir = ctx.actions.declare_directory(ctx.label.name)
    export_args = ctx.actions.args()
    export_args.add(output_dir.path)

    inputs = []
    seen_destinations = {}
    for target, destination in sorted(
        ctx.attr.exports.items(),
        key = lambda item: str(item[0].label),
    ):
        files = target.files.to_list()
        if len(files) != 1:
            fail(
                "sonic_export_to_target_tree(%r): %s must produce exactly one file, got %d." % (
                    ctx.label.name,
                    target.label,
                    len(files),
                )
            )

        normalized_destination = _normalize_export_path(destination)
        previous_owner = seen_destinations.get(normalized_destination)
        if previous_owner:
            fail(
                "sonic_export_to_target_tree(%r): destination %r is claimed by both %s and %s." % (
                    ctx.label.name,
                    normalized_destination,
                    previous_owner,
                    target.label,
                )
            )

        seen_destinations[normalized_destination] = target.label
        export_args.add("%s=%s" % (files[0].path, normalized_destination))
        inputs.append(files[0])

    ctx.actions.run(
        executable = ctx.executable._exporter,
        inputs = depset(inputs),
        outputs = [output_dir],
        arguments = [export_args],
        mnemonic = "SonicExportTargetTree",
        progress_message = "Exporting %d SONiC artifacts into %s" % (
            len(inputs),
            ctx.label.name,
        ),
        tools = [ctx.executable._exporter],
    )

    return [DefaultInfo(files = depset([output_dir]))]

_sonic_export_to_target_tree = rule(
    implementation = _sonic_export_to_target_tree_impl,
    attrs = {
        "exports": attr.label_keyed_string_dict(
            allow_files = True,
            mandatory = True,
            doc = "Mapping from single-file-producing labels to legacy target/ destinations.",
        ),
        "_exporter": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:export_target_tree"),
        ),
    },
    doc = "Copies Bazel outputs into a declared directory matching the legacy target/ layout.",
)

def sonic_export_to_target_tree(name, exports, **kwargs):
    _sonic_export_to_target_tree(
        name = name,
        exports = exports,
        **kwargs
    )
