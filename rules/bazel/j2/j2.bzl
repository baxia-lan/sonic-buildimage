"""Jinja2 template rendering at Bazel build time.

Currently in Make, Jinja2 templates are rendered at container start by
docker-config-engine. This rule moves static templates to build time,
eliminating the need for docker-config-engine in service images.

Templates with truly runtime-dynamic values (interface IPs, etc.) still
render at runtime via a minimal Python script, but those should be the
exception, not the rule.

Usage:
    j2_render(
        name = "supervisord_conf",
        template = ":supervisord.conf.j2",
        vars = ":build_vars.json",
        output = "supervisord.conf",
    )
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# ── j2_render ─────────────────────────────────────────────────────────────────

def _j2_render_impl(ctx):
    template = ctx.file.template
    vars_file = ctx.file.vars
    output = ctx.outputs.output

    args = ctx.actions.args()
    args.add(template.path)
    if vars_file:
        args.add("--vars", vars_file.path)
    args.add("--undefined", "strict")
    args.add("-o", output.path)

    inputs = [template]
    if vars_file:
        inputs.append(vars_file)

    ctx.actions.run(
        inputs = inputs,
        outputs = [output],
        executable = ctx.executable._j2cli,
        arguments = [args],
        mnemonic = "J2Render",
        progress_message = "Rendering Jinja2 template %s" % template.basename,
    )

    return [DefaultInfo(files = depset([output]))]

j2_render = rule(
    implementation = _j2_render_impl,
    attrs = {
        "template": attr.label(
            allow_single_file = [".j2"],
            mandatory = True,
            doc = "Jinja2 template file.",
        ),
        "vars": attr.label(
            allow_single_file = [".json", ".yaml", ".yml"],
            doc = "JSON or YAML file providing template variables.",
        ),
        "output": attr.output(
            mandatory = True,
            doc = "Output file path.",
        ),
        "_j2cli": attr.label(
            default = "//tools:j2cli",
            executable = True,
            cfg = "exec",
            doc = "j2cli binary.",
        ),
    },
)

# ── j2_render_batch ───────────────────────────────────────────────────────────

def j2_render_batch(
        name,
        templates,
        vars,
        outputs,
        visibility = None):
    """Render multiple Jinja2 templates with the same vars file.

    Args:
        name:      Base name (each template becomes <name>_<template_stem>).
        templates: Dict mapping template label to output filename.
        vars:      Label for the shared variables file.
        outputs:   (unused — inferred from templates dict).
        visibility: Bazel visibility.
    """
    for template_label, output_name in templates.items():
        stem = paths.basename(template_label).replace(".j2", "")
        j2_render(
            name = name + "_" + stem,
            template = template_label,
            vars = vars,
            output = output_name,
            visibility = visibility,
        )
