"""Internal source manifests for migrated SONiC Bazel artifacts."""

SonicSourceInfo = provider(
    doc = "Propagates source ownership metadata for migrated SONiC artifacts.",
    fields = {
        "development_branch": "Preferred development branch for the source tree.",
        "development_remote": "Preferred development remote for the source tree.",
        "label": "Canonical Bazel label string for this source.",
        "manifest": "JSON manifest output for this source.",
        "nested_submodule_paths": "Nested submodule paths owned by this source manifest.",
        "overlay_policy": "Migration policy for Bazel ownership of this source.",
        "source_kind": "Source location kind such as submodule or workspace_dir.",
        "source_path": "Workspace-relative source directory for this source.",
        "upstream_repo": "Upstream repository slug when the source is submodule-backed.",
    },
)

def _source_manifest_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".source.json")
    payload = {
        "label": str(ctx.label),
        "source_path": ctx.attr.source_path,
        "source_kind": ctx.attr.source_kind,
        "upstream_repo": ctx.attr.upstream_repo if ctx.attr.upstream_repo else None,
        "development_remote": ctx.attr.development_remote,
        "development_branch": ctx.attr.development_branch,
        "overlay_policy": ctx.attr.overlay_policy,
        "nested_submodule_paths": ctx.attr.nested_submodule_paths,
        "notes": ctx.attr.notes,
    }
    ctx.actions.write(output, json.encode(payload) + "\n")
    return [
        DefaultInfo(files = depset([output])),
        SonicSourceInfo(
            development_branch = ctx.attr.development_branch,
            development_remote = ctx.attr.development_remote,
            label = str(ctx.label),
            manifest = output,
            nested_submodule_paths = ctx.attr.nested_submodule_paths,
            overlay_policy = ctx.attr.overlay_policy,
            source_kind = ctx.attr.source_kind,
            source_path = ctx.attr.source_path,
            upstream_repo = ctx.attr.upstream_repo,
        ),
    ]

_source_manifest = rule(
    implementation = _source_manifest_impl,
    attrs = {
        "source_path": attr.string(mandatory = True),
        "source_kind": attr.string(mandatory = True),
        "upstream_repo": attr.string(),
        "development_remote": attr.string(default = "origin"),
        "development_branch": attr.string(default = "codex"),
        "overlay_policy": attr.string(default = "overlay_first"),
        "nested_submodule_paths": attr.string_list(),
        "notes": attr.string_list(),
    },
    doc = "Writes a JSON manifest describing a migrated SONiC source tree.",
)

def sonic_source_manifest(name, **kwargs):
    _source_manifest(
        name = name,
        **kwargs
    )
