"""Bzlmod extensions for pinned non-module dependencies."""

load("//bazel/repositories:repositories.bzl", "locked_http_archive", "locked_http_file")

archive = tag_class(attrs = {
    "name": attr.string(mandatory = True),
    "urls": attr.string_list(mandatory = True),
    "sha256": attr.string(mandatory = True),
    "strip_prefix": attr.string(default = ""),
})

file = tag_class(attrs = {
    "name": attr.string(mandatory = True),
    "urls": attr.string_list(mandatory = True),
    "sha256": attr.string(mandatory = True),
})

def _non_module_dependencies_impl(module_ctx):
    seen = {}

    for mod in module_ctx.modules:
        for dep in mod.tags.archive:
            if dep.name in seen:
                fail("Duplicate non-module archive dependency: %s" % dep.name)
            seen[dep.name] = True
            locked_http_archive(
                name = dep.name,
                urls = dep.urls,
                sha256 = dep.sha256,
                strip_prefix = dep.strip_prefix,
            )

        for dep in mod.tags.file:
            if dep.name in seen:
                fail("Duplicate non-module file dependency: %s" % dep.name)
            seen[dep.name] = True
            locked_http_file(
                name = dep.name,
                urls = dep.urls,
                sha256 = dep.sha256,
            )

non_module_dependencies = module_extension(
    implementation = _non_module_dependencies_impl,
    tag_classes = {
        "archive": archive,
        "file": file,
    },
)
