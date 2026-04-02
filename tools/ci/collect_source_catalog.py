#!/usr/bin/env python3
"""Collects migrated SONiC source ownership and validates artifact coverage."""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_LABELS = ("//sources/...", "//packages/...", "//images/...")
TRACKED_SOURCE_ARTIFACT_KINDS = {"deb", "wheel", "go_binary", "oci_image"}


def repo_root_from(path: Path) -> Path:
    return path.resolve().parents[2]


def run(command: list[str], cwd: Path) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True)


def build_if_needed(repo_root: Path, bazel: str, labels: list[str], skip_build: bool) -> None:
    if skip_build:
        return
    subprocess.run([bazel, "--batch", "build", "--config=ci", *labels], cwd=repo_root, check=True, text=True)


def cquery_output_paths(repo_root: Path, bazel: str, labels: list[str]) -> list[Path]:
    query_expr = "set(" + " ".join(labels) + ")"
    output = run(
        [
            bazel,
            "--batch",
            "cquery",
            "--config=ci",
            "--output=starlark",
            "--starlark:expr=\"\\n\".join([f.path for f in target.files.to_list()])",
            query_expr,
        ],
        repo_root,
    )
    paths = []
    for line in output.splitlines():
        if not line:
            continue
        path = Path(line)
        if not path.is_absolute():
            path = repo_root / path
        paths.append(path)
    return paths


def load_json_registry(paths: list[Path], suffix: str) -> dict[str, dict]:
    registry = {}
    for path in paths:
        if not path.name.endswith(suffix):
            continue
        payload = json.loads(path.read_text())
        payload["label"] = payload["label"].lstrip("@")
        registry[payload["label"]] = payload
    return registry


def markdown_report(payload: dict) -> str:
    lines = [
        "# SONiC Source Catalog",
        "",
        f"Generated: {payload['generated_at_utc']}",
        "",
        "## Sources",
        "",
    ]
    for label, source in sorted(payload["sources"].items()):
        consumers = payload["consumers"].get(label, [])
        lines.append(f"### {label}")
        lines.append("")
        lines.append(f"- source_path: {source['source_path']}")
        lines.append(f"- source_kind: {source['source_kind']}")
        lines.append(f"- upstream_repo: {source.get('upstream_repo') or 'workspace-local'}")
        lines.append(f"- consumers: {len(consumers)}")
        lines.append("")
    if payload["validation_errors"]:
        lines.extend([
            "## Validation Errors",
            "",
        ])
        for item in payload["validation_errors"]:
            lines.append(f"- {item}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect migrated SONiC source ownership and validate artifact coverage.")
    parser.add_argument("labels", nargs="*", default=list(DEFAULT_LABELS))
    parser.add_argument("--out-dir", default="out/bazel-migration/source-catalog")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    repo_root = repo_root_from(Path(__file__))
    bazel = str(repo_root / "tools/bazel/bazelw")

    build_if_needed(repo_root, bazel, list(args.labels), args.skip_build)
    output_paths = cquery_output_paths(repo_root, bazel, list(args.labels))
    sources = load_json_registry(output_paths, ".source.json")
    artifacts = load_json_registry(output_paths, ".lock.json")

    consumers: dict[str, list[str]] = defaultdict(list)
    errors: list[str] = []
    for artifact in artifacts.values():
        if artifact["artifact_kind"] not in TRACKED_SOURCE_ARTIFACT_KINDS:
            continue

        source_path = artifact.get("source_path")
        if not source_path:
            continue

        bound_sources = artifact.get("sources", [])
        if not bound_sources:
            errors.append(f"{artifact['label']}: missing source manifest binding for {source_path}")
            continue

        bound_labels = []
        bound_paths = set()
        for source in bound_sources:
            label = source["label"].lstrip("@")
            bound_labels.append(label)
            bound_paths.add(source["source_path"])
            consumers[label].append(artifact["label"])

        if source_path not in bound_paths:
            errors.append(
                f"{artifact['label']}: source_path {source_path} is not covered by source manifests {', '.join(sorted(bound_labels))}"
            )

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "labels": list(args.labels),
        "sources": dict(sorted(sources.items())),
        "consumers": {label: sorted(items) for label, items in sorted(consumers.items())},
        "validation_errors": errors,
    }

    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "source_catalog.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    (out_dir / "source_catalog.md").write_text(markdown_report(payload))

    if args.stdout:
        print(markdown_report(payload), end="")
    if errors:
        for error in errors:
            print(error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
