"""Minimal Jinja2 CLI renderer for build-time template processing."""

import argparse
import json
import sys

import jinja2
import yaml


def main():
    parser = argparse.ArgumentParser(description="Render Jinja2 templates")
    parser.add_argument("template", help="Path to .j2 template file")
    parser.add_argument("--vars", help="Path to JSON/YAML vars file")
    parser.add_argument("--undefined", default="strict",
                        choices=["strict", "undefined"])
    parser.add_argument("-o", "--output", required=True,
                        help="Output file path")
    args = parser.parse_args()

    with open(args.template) as f:
        template_str = f.read()

    variables = {}
    if args.vars:
        with open(args.vars) as f:
            if args.vars.endswith((".yaml", ".yml")):
                variables = yaml.safe_load(f)
            else:
                variables = json.load(f)

    undefined_cls = (jinja2.StrictUndefined if args.undefined == "strict"
                     else jinja2.Undefined)
    env = jinja2.Environment(undefined=undefined_cls)
    template = env.from_string(template_str)
    result = template.render(**variables)

    with open(args.output, "w") as f:
        f.write(result)


if __name__ == "__main__":
    main()
