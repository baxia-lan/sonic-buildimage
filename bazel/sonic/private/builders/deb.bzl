"""Concrete SONiC Debian package builders."""

load("//bazel/sonic/private:metadata.bzl", "COMMON_ARTIFACT_ATTRS", "SonicArtifactInfo")
load("//bazel/sonic/private:sources.bzl", "SonicSourceInfo")

def _labels(targets):
    return [str(target.label) for target in targets]

def _artifact_infos(targets):
    return [target[SonicArtifactInfo] for target in targets if SonicArtifactInfo in target]

def _source_infos(targets):
    return [target[SonicSourceInfo] for target in targets if SonicSourceInfo in target]

def _write_package_artifact_metadata(ctx):
    manifest_output = ctx.actions.declare_file(ctx.attr.output_name + ".manifest.json")
    lock_output = ctx.actions.declare_file(ctx.attr.output_name + ".lock.json")

    runtime_infos = _artifact_infos(ctx.attr.runtime_deps)
    wheel_infos = _artifact_infos(ctx.attr.wheel_deps)
    fragment_infos = _artifact_infos(ctx.attr.fragments)
    bound_sources = _source_infos(ctx.attr.sources)
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
            for info in bound_sources
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
            for info in bound_sources
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

    return struct(
        graph_depth = graph_depth,
        lock = lock_output,
        manifest = manifest_output,
        transitive_labels = transitive_labels,
    )

def _sonic_deb_builder_impl(ctx):
    metadata = _write_package_artifact_metadata(ctx)
    deb_output = ctx.actions.declare_file(ctx.attr.output_name)

    args = ctx.actions.args()
    args.add("--output", deb_output.path)
    args.add("--docker-image", ctx.attr.docker_image)
    args.add("--docker-platform", ctx.attr.docker_platform)
    args.add("--source-root", ctx.attr.source_root)
    args.add("--deb-pattern", ctx.attr.deb_pattern)
    args.add("--package-name", ctx.attr.package_name)
    args.add("--version", ctx.attr.package_version)
    args.add("--arch", ctx.attr.package_arch)

    prefix = ctx.attr.source_root + "/"
    for src in sorted(ctx.files.builder_srcs, key = lambda file: file.short_path):
        if not src.short_path.startswith(prefix):
            fail("%s is outside declared source_root %s" % (src.short_path, ctx.attr.source_root))
        args.add("--src-map", "%s=%s" % (src.path, src.short_path[len(prefix):]))

    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = depset(ctx.files.builder_srcs),
        outputs = [deb_output],
        arguments = [args],
        tools = [ctx.executable._builder],
        mnemonic = "SonicDebPackage",
        progress_message = "Building SONiC Debian package %s" % ctx.label,
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
        },
    )

    return [
        DefaultInfo(files = depset([deb_output, metadata.manifest, metadata.lock])),
        SonicArtifactInfo(
            artifact_kind = ctx.attr.artifact_kind,
            artifact_labels = metadata.transitive_labels,
            composition_depth = metadata.graph_depth,
            label = str(ctx.label),
            lock = metadata.lock,
            manifest = metadata.manifest,
        ),
    ]

_sonic_deb_builder = rule(
    implementation = _sonic_deb_builder_impl,
    attrs = dict(
        COMMON_ARTIFACT_ATTRS,
        builder_srcs = attr.label_list(
            allow_files = True,
            mandatory = True,
        ),
        source_root = attr.string(mandatory = True),
        output_name = attr.string(mandatory = True),
        deb_pattern = attr.string(mandatory = True),
        package_name = attr.string(mandatory = True),
        package_version = attr.string(mandatory = True),
        package_arch = attr.string(default = "amd64"),
        docker_image = attr.string(default = "sonic-bazel-legacy-bridge-helper:bookworm"),
        docker_platform = attr.string(default = "linux/amd64"),
        _builder = attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//tools/bazel:build_deb_package"),
        ),
    ),
    doc = "Builds a real Debian package while preserving SONiC artifact metadata side outputs.",
)

def sonic_deb_builder(name, **kwargs):
    _sonic_deb_builder(
        name = name,
        artifact_kind = "deb",
        **kwargs
    )
