"""Manifest-backed SONiC artifact APIs.

The migration starts by moving graph ownership into Bazel-native manifests before
the final concrete builders replace the legacy Make outputs. Each public macro
currently emits deterministic JSON outputs that record the legacy artifact
shape, source ownership, dependency edges, and a Bazel-resolved lock view for
the migrated slice.
"""

load("//bazel/sonic/private:sources.bzl", "SonicSourceInfo")

SonicArtifactInfo = provider(
    doc = "Propagates SONiC artifact metadata through the Bazel migration graph.",
    fields = {
        "artifact_kind": "Logical artifact kind such as deb, wheel, or oci_image.",
        "artifact_labels": "depset of transitive artifact labels.",
        "composition_depth": "Longest dependency chain depth rooted at this artifact.",
        "label": "Canonical Bazel label string for this artifact.",
        "lock": "Resolved lock JSON output file for this artifact.",
        "manifest": "Primary manifest JSON output file for this artifact.",
    },
)

def _labels(targets):
    return [str(target.label) for target in targets]

def _artifact_infos(targets):
    return [target[SonicArtifactInfo] for target in targets if SonicArtifactInfo in target]

def _source_infos(targets):
    return [target[SonicSourceInfo] for target in targets if SonicSourceInfo in target]

def _artifact_manifest_impl(ctx):
    manifest_output = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    lock_output = ctx.actions.declare_file(ctx.label.name + ".lock.json")

    dep_infos = _artifact_infos(ctx.attr.deps)
    runtime_infos = _artifact_infos(ctx.attr.runtime_deps)
    wheel_infos = _artifact_infos(ctx.attr.wheel_deps)
    fragment_infos = _artifact_infos(ctx.attr.fragments)
    source_infos = _source_infos(ctx.attr.sources)
    base_info = ctx.attr.base[SonicArtifactInfo] if ctx.attr.base and SonicArtifactInfo in ctx.attr.base else None

    graph_children = runtime_infos + wheel_infos + fragment_infos
    if base_info:
        graph_children.append(base_info)

    transitive_labels = depset(
        direct = [str(ctx.label)],
        transitive = [info.artifact_labels for info in graph_children],
    )
    graph_depth = 1
    if graph_children:
        graph_depth += max([info.composition_depth for info in graph_children])

    manifest = {
        "artifact_kind": ctx.attr.artifact_kind,
        "label": str(ctx.label),
        "migration_stage": ctx.attr.migration_stage,
        "legacy_artifact": ctx.attr.legacy_artifact if ctx.attr.legacy_artifact else None,
        "legacy_dockerfile": ctx.attr.legacy_dockerfile if ctx.attr.legacy_dockerfile else None,
        "source_path": ctx.attr.source_path if ctx.attr.source_path else None,
        "source_makefiles": ctx.attr.source_makefiles,
        "submodule_paths": ctx.attr.submodule_paths,
        "sources": [
            {
                "label": info.label,
                "source_path": info.source_path,
                "source_kind": info.source_kind,
                "upstream_repo": info.upstream_repo if info.upstream_repo else None,
                "development_remote": info.development_remote,
                "development_branch": info.development_branch,
                "overlay_policy": info.overlay_policy,
                "nested_submodule_paths": info.nested_submodule_paths,
            }
            for info in source_infos
        ],
        "dependencies": {
            "build": {
                "bazel": _labels(ctx.attr.deps),
                "legacy": ctx.attr.legacy_deps,
            },
            "runtime": {
                "bazel": _labels(ctx.attr.runtime_deps),
                "legacy": ctx.attr.legacy_runtime_deps,
            },
            "python_wheels": {
                "bazel": _labels(ctx.attr.wheel_deps),
                "legacy": ctx.attr.legacy_wheel_deps,
            },
        },
        "composition": {
            "base": str(ctx.attr.base.label) if ctx.attr.base else None,
            "legacy_base": ctx.attr.legacy_base if ctx.attr.legacy_base else None,
            "fragments": _labels(ctx.attr.fragments),
            "legacy_fragments": ctx.attr.legacy_fragments,
            "files": ctx.attr.files,
        },
        "platform": {
            "machine": ctx.attr.machine if ctx.attr.machine else None,
            "platform_name": ctx.attr.platform_name if ctx.attr.platform_name else None,
            "dependent_machines": ctx.attr.dependent_machines,
            "configured_arches": ctx.attr.configured_arches,
        },
        "installer": {
            "format": ctx.attr.installer_format if ctx.attr.installer_format else None,
            "payloads": {
                "installs": ctx.attr.legacy_installs,
                "lazy_installs": ctx.attr.legacy_lazy_installs,
                "lazy_build_installs": ctx.attr.legacy_lazy_build_installs,
                "docker_images": ctx.attr.legacy_docker_images,
            },
        },
        "metadata": dict(sorted(ctx.attr.metadata.items())),
        "notes": ctx.attr.notes,
    }

    lock = {
        "artifact_kind": ctx.attr.artifact_kind,
        "label": str(ctx.label),
        "migration_stage": ctx.attr.migration_stage,
        "legacy_artifact": ctx.attr.legacy_artifact if ctx.attr.legacy_artifact else None,
        "legacy_dockerfile": ctx.attr.legacy_dockerfile if ctx.attr.legacy_dockerfile else None,
        "source_path": ctx.attr.source_path if ctx.attr.source_path else None,
        "submodule_paths": ctx.attr.submodule_paths,
        "source_makefiles": ctx.attr.source_makefiles,
        "sources": [
            {
                "label": info.label,
                "source_path": info.source_path,
                "source_kind": info.source_kind,
                "upstream_repo": info.upstream_repo if info.upstream_repo else None,
                "development_remote": info.development_remote,
                "development_branch": info.development_branch,
                "overlay_policy": info.overlay_policy,
                "nested_submodule_paths": info.nested_submodule_paths,
            }
            for info in source_infos
        ],
        "direct_dependencies": {
            "build": _labels(ctx.attr.deps),
            "runtime": _labels(ctx.attr.runtime_deps),
            "python_wheels": _labels(ctx.attr.wheel_deps),
            "base": str(ctx.attr.base.label) if ctx.attr.base else None,
            "fragments": _labels(ctx.attr.fragments),
            "sources": _labels(ctx.attr.sources),
        },
        "platform": {
            "machine": ctx.attr.machine if ctx.attr.machine else None,
            "platform_name": ctx.attr.platform_name if ctx.attr.platform_name else None,
            "dependent_machines": ctx.attr.dependent_machines,
            "configured_arches": ctx.attr.configured_arches,
        },
        "installer": {
            "format": ctx.attr.installer_format if ctx.attr.installer_format else None,
            "payloads": {
                "installs": ctx.attr.legacy_installs,
                "lazy_installs": ctx.attr.legacy_lazy_installs,
                "lazy_build_installs": ctx.attr.legacy_lazy_build_installs,
                "docker_images": ctx.attr.legacy_docker_images,
            },
        },
        "graph": {
            "composition_depth": graph_depth,
            "transitive_artifact_labels": sorted(transitive_labels.to_list()),
            "transitive_artifact_count": len(transitive_labels.to_list()),
        },
        "metadata": dict(sorted(ctx.attr.metadata.items())),
    }

    ctx.actions.write(manifest_output, json.encode(manifest) + "\n")
    ctx.actions.write(lock_output, json.encode(lock) + "\n")
    return [
        DefaultInfo(files = depset([manifest_output, lock_output])),
        SonicArtifactInfo(
            artifact_kind = ctx.attr.artifact_kind,
            artifact_labels = transitive_labels,
            composition_depth = graph_depth,
            label = str(ctx.label),
            lock = lock_output,
            manifest = manifest_output,
        ),
    ]

_artifact_manifest = rule(
    implementation = _artifact_manifest_impl,
    attrs = {
        "artifact_kind": attr.string(mandatory = True),
        "migration_stage": attr.string(default = "manifest_only"),
        "legacy_artifact": attr.string(),
        "legacy_dockerfile": attr.string(),
        "source_path": attr.string(),
        "source_makefiles": attr.string_list(),
        "submodule_paths": attr.string_list(),
        "deps": attr.label_list(),
        "legacy_deps": attr.string_list(),
        "runtime_deps": attr.label_list(),
        "legacy_runtime_deps": attr.string_list(),
        "wheel_deps": attr.label_list(),
        "legacy_wheel_deps": attr.string_list(),
        "sources": attr.label_list(),
        "base": attr.label(),
        "legacy_base": attr.string(),
        "fragments": attr.label_list(),
        "legacy_fragments": attr.string_list(),
        "files": attr.string_list(),
        "machine": attr.string(),
        "platform_name": attr.string(),
        "dependent_machines": attr.string_list(),
        "configured_arches": attr.string_list(),
        "installer_format": attr.string(),
        "legacy_installs": attr.string_list(),
        "legacy_lazy_installs": attr.string_list(),
        "legacy_lazy_build_installs": attr.string_list(),
        "legacy_docker_images": attr.string_list(),
        "metadata": attr.string_dict(),
        "notes": attr.string_list(),
    },
    doc = "Writes a JSON manifest for a SONiC artifact migration slice.",
)

def sonic_deb_package(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "deb",
        **kwargs
    )

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

def sonic_oci_image(name, **kwargs):
    _artifact_manifest(
        name = name,
        artifact_kind = "oci_image",
        **kwargs
    )

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
