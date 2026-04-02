#!/usr/bin/env python3
"""Collects image composition metrics from Bazel-generated SONiC artifact locks."""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_LABELS = ("//packages/...", "//images/...")
NETWORK_TOKENS = {
    "apt_get": "apt-get",
    "pip_install": "pip install",
    "pip3_install": "pip3 install",
    "curl": "curl ",
    "wget": "wget ",
}


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


def collapse_logical_lines(text: str) -> list[str]:
    logical = []
    buffer = ""
    for raw in text.splitlines():
        line = raw.rstrip()
        if not buffer:
            buffer = line
        else:
            buffer += " " + line.lstrip()
        if line.endswith("\\"):
            buffer = buffer[:-1].rstrip()
            continue
        logical.append(buffer.strip())
        buffer = ""
    if buffer.strip():
        logical.append(buffer.strip())
    return logical


def dockerfile_metrics(repo_root: Path, dockerfile: str | None) -> dict:
    if not dockerfile:
        return {
            "run_commands": 0,
            "network_installs": {key: 0 for key in NETWORK_TOKENS},
        }

    path = repo_root / dockerfile
    lines = collapse_logical_lines(path.read_text(errors="ignore")) if path.exists() else []
    run_lines = [line for line in lines if line.upper().startswith("RUN ")]
    counts = {key: 0 for key in NETWORK_TOKENS}
    for line in run_lines:
        lower = line.lower()
        for key, token in NETWORK_TOKENS.items():
            if token in lower:
                counts[key] += 1

    return {
        "run_commands": len(run_lines),
        "network_installs": counts,
    }


def load_locks(lock_paths: list[Path]) -> dict[str, dict]:
    registry = {}
    for path in lock_paths:
        payload = json.loads(path.read_text())
        payload["label"] = payload["label"].lstrip("@")
        direct = payload.get("direct_dependencies", {})
        for key in ("build", "runtime", "python_wheels", "fragments"):
            direct[key] = [item.lstrip("@") for item in direct.get(key, [])]
        if direct.get("base"):
            direct["base"] = direct["base"].lstrip("@")
        if "graph" in payload:
            payload["graph"]["transitive_artifact_labels"] = [
                item.lstrip("@") for item in payload["graph"].get("transitive_artifact_labels", [])
            ]
        registry[payload["label"]] = payload
    return registry


def walk_runtime_graph(label: str, registry: dict[str, dict], visited: set[str], mentions: list[str]) -> None:
    if label in visited:
        return
    visited.add(label)
    node = registry.get(label)
    if node is None:
        return

    direct = node.get("direct_dependencies", {})
    next_labels = []
    for key in ("runtime", "python_wheels", "fragments"):
        next_labels.extend(direct.get(key, []))
    if direct.get("base"):
        next_labels.append(direct["base"])

    for child in next_labels:
        mentions.append(child)
        walk_runtime_graph(child, registry, visited, mentions)


def summarize_image(repo_root: Path, label: str, lock: dict, registry: dict[str, dict]) -> dict:
    visited: set[str] = set()
    mentions: list[str] = []
    walk_runtime_graph(label, registry, visited, mentions)
    visited.discard(label)

    runtime_kinds = Counter()
    for item in visited:
        artifact = registry.get(item)
        if artifact:
            runtime_kinds[artifact["artifact_kind"]] += 1

    docker_metrics_value = dockerfile_metrics(repo_root, lock.get("legacy_dockerfile"))
    estimated_layer_count = lock["graph"]["composition_depth"] + docker_metrics_value["run_commands"]

    return {
        "label": label,
        "legacy_dockerfile": lock.get("legacy_dockerfile"),
        "composition_depth": lock["graph"]["composition_depth"],
        "direct_runtime_count": len(lock["direct_dependencies"]["runtime"]),
        "direct_wheel_count": len(lock["direct_dependencies"]["python_wheels"]),
        "direct_fragment_count": len(lock["direct_dependencies"]["fragments"]),
        "transitive_runtime_artifact_count": len(visited),
        "runtime_artifact_kinds": dict(sorted(runtime_kinds.items())),
        "duplicate_dependency_mentions": len(mentions) - len(set(mentions)),
        "dockerfile_run_commands": docker_metrics_value["run_commands"],
        "network_install_ops": docker_metrics_value["network_installs"],
        "estimated_layer_count": estimated_layer_count,
    }


def enforce_budget(images: dict[str, dict], budget_file: Path) -> list[str]:
    if not budget_file.exists():
        return []

    budgets = json.loads(budget_file.read_text())
    errors = []
    for label, budget in budgets.items():
        actual = images.get(label)
        if actual is None:
            errors.append(f"Missing image metrics for budgeted label {label}")
            continue

        for key, maximum in budget.items():
            if key == "max_network_install_ops":
                total_ops = sum(actual["network_install_ops"].values())
                if total_ops > maximum:
                    errors.append(f"{label}: network install ops {total_ops} > {maximum}")
                continue

            metric_name = key[4:] if key.startswith("max_") else key
            actual_value = actual.get(metric_name)
            if actual_value is None:
                errors.append(f"{label}: missing metric for budget key {key}")
                continue
            if actual_value > maximum:
                errors.append(f"{label}: {metric_name} {actual_value} > {maximum}")

    return errors


def markdown_report(payload: dict) -> str:
    lines = [
        "# SONiC Image Metrics",
        "",
        f"Generated: {payload['generated_at_utc']}",
        "",
        "## Images",
        "",
    ]
    for label, metrics in sorted(payload["images"].items()):
        lines.append(f"### {label}")
        lines.append("")
        lines.append(f"- composition_depth: {metrics['composition_depth']}")
        lines.append(f"- transitive_runtime_artifact_count: {metrics['transitive_runtime_artifact_count']}")
        lines.append(f"- duplicate_dependency_mentions: {metrics['duplicate_dependency_mentions']}")
        lines.append(f"- dockerfile_run_commands: {metrics['dockerfile_run_commands']}")
        lines.append(f"- estimated_layer_count: {metrics['estimated_layer_count']}")
        lines.append(f"- network_install_ops: {sum(metrics['network_install_ops'].values())}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect image metrics from Bazel-generated SONiC lock files.")
    parser.add_argument("labels", nargs="*", default=list(DEFAULT_LABELS))
    parser.add_argument("--out-dir", default="out/bazel-migration/image-metrics")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--budget-file", default="tools/ci/image_budgets.json")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    repo_root = repo_root_from(Path(__file__))
    bazel = str(repo_root / "tools/bazel/bazelw")

    build_if_needed(repo_root, bazel, list(args.labels), args.skip_build)
    output_paths = cquery_output_paths(repo_root, bazel, list(args.labels))
    lock_paths = sorted(path for path in output_paths if path.name.endswith(".lock.json"))
    registry = load_locks(lock_paths)

    images = {}
    for label, lock in registry.items():
        if lock["artifact_kind"] != "oci_image":
            continue
        images[label] = summarize_image(repo_root, label, lock, registry)

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "labels": list(args.labels),
        "images": images,
    }

    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents = True, exist_ok = True)
    (out_dir / "image_metrics.json").write_text(json.dumps(payload, indent = 2, sort_keys = True) + "\n")
    (out_dir / "image_metrics.md").write_text(markdown_report(payload))

    errors = enforce_budget(images, repo_root / args.budget_file)
    if args.stdout:
        print(markdown_report(payload), end = "")
    if errors:
        for error in errors:
            print(error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
