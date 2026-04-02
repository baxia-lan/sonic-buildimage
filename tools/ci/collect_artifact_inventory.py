#!/usr/bin/env python3
"""Collects a reproducible Make-era artifact inventory for Bazel migration."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse


ARTIFACT_GROUPS = {
    "docker_images": "SONIC_DOCKER_IMAGES",
    "python_wheels": "SONIC_PYTHON_WHEELS",
    "make_debs": "SONIC_MAKE_DEBS",
    "dpkg_debs": "SONIC_DPKG_DEBS",
    "derived_debs": "SONIC_DERIVED_DEBS",
    "installers": "SONIC_INSTALLERS",
}

FOCUS_CHAIN = {
    "DOCKER_BASE_BULLSEYE": "dockers/docker-base-bullseye/Dockerfile.j2",
    "DOCKER_CONFIG_ENGINE_BULLSEYE": "dockers/docker-config-engine-bullseye/Dockerfile.j2",
    "DOCKER_SWSS_LAYER_BULLSEYE": "dockers/docker-swss-layer-bullseye/Dockerfile.j2",
    "DOCKER_ORCHAGENT": "dockers/docker-orchagent/Dockerfile.j2",
}

FOCUS_SUBMODULE_PATHS = (
    "src/sonic-swss-common",
    "src/sonic-sairedis",
    "src/sonic-swss",
    "src/scapy",
    "src/sonic-dash-api",
)

BAZEL_FILENAMES = {
    "BUILD",
    "BUILD.bazel",
    "MODULE.bazel",
    "REPO.bazel",
    "WORKSPACE",
    "WORKSPACE.bazel",
}

ROOT_BUILD_MARKERS = (
    "BUILD",
    "BUILD.bazel",
    "MODULE.bazel",
    "WORKSPACE",
    "WORKSPACE.bazel",
    "Makefile",
    "pyproject.toml",
    "setup.py",
    "go.mod",
    "Cargo.toml",
    "CMakeLists.txt",
)

FOCUS_FIELDS = (
    "DEPENDS",
    "PYTHON_WHEELS",
    "LOAD_DOCKERS",
    "FILES",
    "DBG_DEPENDS",
    "DBG_IMAGE_PACKAGES",
)

VAR_ASSIGN_RE = re.compile(r"^([A-Z0-9_][A-Z0-9_\-]*)\s*=\s*(.+)$")
GROUP_MEMBER_RE = {
    group: re.compile(rf"^{make_var}\s*\+=\s*\$\(([A-Z0-9_][A-Z0-9_\-]*)\)$")
    for group, make_var in ARTIFACT_GROUPS.items()
}
FOCUS_ASSIGN_RE = re.compile(
    r"^\$\(([A-Z0-9_][A-Z0-9_\-]*)\)_([A-Z_]+)\s*(\+?=)\s*(.+)$"
)
VAR_REF_RE = re.compile(r"\$\(([A-Z0-9_][A-Z0-9_\-]*)\)")


@dataclass(frozen=True)
class SourceLine:
    path: str
    line: int
    text: str


def repo_root_from(path: Path) -> Path:
    return path.resolve().parents[2]


def iter_logical_lines(path: Path) -> Iterable[tuple[int, str]]:
    start_line = 0
    buffer = ""
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.rstrip()
        if not buffer:
            start_line = line_number
        if line.endswith("\\"):
            buffer += line[:-1] + " "
            continue
        logical = (buffer + line).strip()
        buffer = ""
        if logical:
            yield start_line, logical
    if buffer.strip():
        yield start_line, buffer.strip()


def scan_artifacts(repo_root: Path) -> dict:
    artifact_defs: dict[str, SourceLine] = {}
    group_members: dict[str, dict[str, list[SourceLine]]] = {
        group: defaultdict(list) for group in ARTIFACT_GROUPS
    }
    focus_details: dict[str, dict[str, list[dict[str, object]]]] = {
        focus_var: {field.lower(): [] for field in FOCUS_FIELDS}
        for focus_var in FOCUS_CHAIN
    }

    mk_files = sorted(
        list((repo_root / "rules").rglob("*.mk")) +
        list((repo_root / "platform").rglob("*.mk"))
    )
    for path in mk_files:
        rel_path = path.relative_to(repo_root).as_posix()
        for line_number, logical in iter_logical_lines(path):
            definition = VAR_ASSIGN_RE.match(logical)
            if definition:
                name, value = definition.groups()
                artifact_defs.setdefault(
                    name,
                    SourceLine(path=rel_path, line=line_number, text=value.strip()),
                )

            for group, matcher in GROUP_MEMBER_RE.items():
                membership = matcher.match(logical)
                if membership:
                    artifact_var = membership.group(1)
                    group_members[group][artifact_var].append(
                        SourceLine(path=rel_path, line=line_number, text=logical)
                    )

            focus_assignment = FOCUS_ASSIGN_RE.match(logical)
            if not focus_assignment:
                continue

            focus_var, field, _operator, raw_value = focus_assignment.groups()
            if focus_var not in focus_details or field not in FOCUS_FIELDS:
                continue

            focus_details[focus_var][field.lower()].append(
                {
                    "path": rel_path,
                    "line": line_number,
                    "raw": raw_value.strip(),
                    "references": VAR_REF_RE.findall(raw_value),
                }
            )

    grouped = {}
    counts = {}
    for group, members in group_members.items():
        artifacts = []
        for artifact_var in sorted(members):
            definition = artifact_defs.get(artifact_var)
            artifacts.append(
                {
                    "var": artifact_var,
                    "definition": {
                        "path": definition.path,
                        "line": definition.line,
                        "raw": definition.text,
                    } if definition else None,
                    "memberships": [
                        {
                            "path": source.path,
                            "line": source.line,
                        }
                        for source in members[artifact_var]
                    ],
                }
            )
        grouped[group] = artifacts
        counts[group] = len(artifacts)

    return {
        "counts": counts,
        "groups": grouped,
        "focus_chain": focus_details,
    }


def read_gitmodules(repo_root: Path) -> dict:
    return read_gitmodules_file(repo_root / ".gitmodules")


def read_gitmodules_file(gitmodules: Path) -> dict:
    items = []
    current = None
    if not gitmodules.exists():
        return {"count": 0, "items": []}

    for line in gitmodules.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("[submodule "):
            if current:
                items.append(current)
            current = {"name": stripped[len("[submodule "):].rstrip("]").strip('"')}
            continue
        if current and "=" in stripped:
            key, value = [part.strip() for part in stripped.split("=", 1)]
            current[key] = value
    if current:
        items.append(current)

    items.sort(key=lambda item: item.get("path", item["name"]))
    return {"count": len(items), "items": items}


def github_slug_from(url: str | None) -> str | None:
    if not url:
        return None

    if url.startswith("git@github.com:"):
        slug = url.split(":", 1)[1]
    else:
        parsed = urlparse(url)
        if parsed.netloc != "github.com":
            return None
        slug = parsed.path.lstrip("/")

    if slug.endswith(".git"):
        slug = slug[:-4]
    return slug or None


def infer_migration_policy(url: str | None, makefile_count: int, bazel_file_count: int) -> str:
    if bazel_file_count and makefile_count:
        return "direct-edit candidate (mixed Make/Bazel)"
    if bazel_file_count:
        return "reuse existing Bazel surface"
    if url and "github.com/sonic-net/" in url:
        return "candidate for forked Bazel migration"
    return "overlay-first preferred"


def collect_submodule_make_surfaces(repo_root: Path, submodules: dict) -> dict:
    items = []
    total_makefiles = 0
    total_bazel_files = 0
    with_makefiles = 0
    with_bazel_files = 0
    focus_items = []
    unique_repos: dict[str, list[str]] = defaultdict(list)

    for submodule in submodules["items"]:
        rel_path = submodule.get("path")
        if not rel_path:
            continue

        root = repo_root / rel_path
        makefiles = []
        bazel_files = []
        present = root.exists() and any(root.iterdir()) if root.exists() else False
        root_markers = []
        nested_submodules = {"count": 0, "items": []}
        if present:
            makefiles = sorted(
                path.relative_to(repo_root).as_posix()
                for path in root.rglob("*")
                if path.is_file() and (path.name == "Makefile" or path.suffix == ".mk")
            )
            bazel_files = sorted(
                path.relative_to(repo_root).as_posix()
                for path in root.rglob("*")
                if path.is_file() and (path.name in BAZEL_FILENAMES or path.suffix == ".bzl")
            )
            root_markers = [
                marker for marker in ROOT_BUILD_MARKERS if (root / marker).exists()
            ]
            nested_submodules = read_gitmodules_file(root / ".gitmodules")

        total_makefiles += len(makefiles)
        total_bazel_files += len(bazel_files)
        if makefiles:
            with_makefiles += 1
        if bazel_files:
            with_bazel_files += 1

        github_slug = github_slug_from(submodule.get("url"))
        if github_slug:
            unique_repos[github_slug].append(rel_path)

        record = {
            "path": rel_path,
            "url": submodule.get("url"),
            "github_slug": github_slug,
            "branch": submodule.get("branch"),
            "present": present,
            "makefile_count": len(makefiles),
            "bazel_file_count": len(bazel_files),
            "root_markers": root_markers,
            "nested_submodule_count": nested_submodules["count"],
            "migration_policy_hint": infer_migration_policy(
                submodule.get("url"),
                len(makefiles),
                len(bazel_files),
            ),
            "sample_makefiles": makefiles[:20],
            "sample_bazel_files": bazel_files[:20],
        }
        items.append(record)
        if rel_path in FOCUS_SUBMODULE_PATHS:
            focus_items.append(record)

    items.sort(key=lambda item: item["path"])
    focus_items.sort(key=lambda item: item["path"])
    return {
        "total_makefiles": total_makefiles,
        "total_bazel_files": total_bazel_files,
        "with_makefiles": with_makefiles,
        "with_bazel_files": with_bazel_files,
        "unique_repo_count": len(unique_repos),
        "duplicate_upstreams": [
            {"github_slug": slug, "paths": sorted(paths)}
            for slug, paths in sorted(unique_repos.items())
            if len(paths) > 1
        ],
        "items": items,
        "focus_items": focus_items,
    }


def collect_base_consumers(repo_root: Path, needle: str) -> list[str]:
    results = []
    for root in ("dockers", "platform", "rules"):
        for path in sorted((repo_root / root).rglob("*")):
            if not path.is_file():
                continue
            if path.suffix not in {".j2", ".mk"}:
                continue
            text = path.read_text(errors="ignore")
            if needle in text:
                results.append(path.relative_to(repo_root).as_posix())
    return results


def build_inventory(repo_root: Path) -> dict:
    artifact_inventory = scan_artifacts(repo_root)
    submodules = read_gitmodules(repo_root)
    submodule_make_surfaces = collect_submodule_make_surfaces(repo_root, submodules)
    config_engine_consumers = collect_base_consumers(repo_root, "docker-config-engine")
    swss_layer_consumers = collect_base_consumers(repo_root, "docker-swss-layer")

    focus_chain = {}
    for artifact_var, dockerfile in FOCUS_CHAIN.items():
        focus_chain[artifact_var] = {
            "dockerfile": dockerfile,
            "details": artifact_inventory["focus_chain"][artifact_var],
        }

    return {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repo_root": repo_root.as_posix(),
        "submodules": submodules,
        "submodule_make_surfaces": submodule_make_surfaces,
        "artifact_counts": artifact_inventory["counts"],
        "artifact_groups": artifact_inventory["groups"],
        "base_consumers": {
            "docker_config_engine_references": {
                "count": len(config_engine_consumers),
                "paths": config_engine_consumers,
            },
            "docker_swss_layer_references": {
                "count": len(swss_layer_consumers),
                "paths": swss_layer_consumers,
            },
        },
        "focus_chain": focus_chain,
    }


def markdown_summary(inventory: dict) -> str:
    lines = [
        "# SONiC Bazel Migration Baseline",
        "",
        f"Generated: {inventory['generated_at_utc']}",
        "",
        "## Summary",
        "",
        f"- Submodules: {inventory['submodules']['count']}",
        f"- Unique top-level upstream repos: {inventory['submodule_make_surfaces']['unique_repo_count']}",
        f"- Submodule Makefiles: {inventory['submodule_make_surfaces']['total_makefiles']}",
        f"- Submodule Bazel files: {inventory['submodule_make_surfaces']['total_bazel_files']}",
        f"- Top-level submodules with Makefiles: {inventory['submodule_make_surfaces']['with_makefiles']}",
        f"- Top-level submodules with Bazel files: {inventory['submodule_make_surfaces']['with_bazel_files']}",
    ]
    for group, count in inventory["artifact_counts"].items():
        lines.append(f"- {group}: {count}")
    lines.extend(
        [
            f"- docker-config-engine references: "
            f"{inventory['base_consumers']['docker_config_engine_references']['count']}",
            f"- docker-swss-layer references: "
            f"{inventory['base_consumers']['docker_swss_layer_references']['count']}",
            "",
            "## Focus Chain",
            "",
        ]
    )

    lines.extend(
        [
            "## Focus Submodules",
            "",
        ]
    )
    for item in inventory["submodule_make_surfaces"]["focus_items"]:
        lines.append(
            f"- {item['path']}: "
            f"{'checked out' if item['present'] else 'not checked out locally'}, "
            f"{item['makefile_count']} Makefile/.mk files, "
            f"{item['bazel_file_count']} Bazel files, "
            f"policy hint: {item['migration_policy_hint']}"
        )
    lines.append("")

    duplicates = inventory["submodule_make_surfaces"]["duplicate_upstreams"]
    if duplicates:
        lines.extend(
            [
                "## Duplicate Upstreams",
                "",
            ]
        )
        for item in duplicates:
            lines.append(f"- {item['github_slug']}: {', '.join(item['paths'])}")
        lines.append("")

    for artifact_var, details in inventory["focus_chain"].items():
        lines.append(f"### {artifact_var}")
        lines.append("")
        lines.append(f"- Dockerfile: `{details['dockerfile']}`")
        for field, values in details["details"].items():
            lines.append(f"- {field}: {len(values)} assignment(s)")
            for item in values:
                refs = ", ".join(item["references"]) if item["references"] else item["raw"]
                lines.append(
                    f"  - {item['path']}:{item['line']} -> {refs}"
                )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def write_outputs(out_dir: Path, inventory: dict) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "artifact_inventory.json").write_text(
        json.dumps(inventory, indent=2, sort_keys=True) + "\n"
    )
    (out_dir / "artifact_inventory.md").write_text(markdown_summary(inventory))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect a Make-era artifact inventory for the Bazel migration."
    )
    parser.add_argument(
        "--out-dir",
        default="out/bazel-migration/baseline",
        help="Directory for the generated JSON and Markdown reports.",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print the Markdown summary to stdout.",
    )
    args = parser.parse_args()

    repo_root = repo_root_from(Path(__file__))
    inventory = build_inventory(repo_root)
    write_outputs(repo_root / args.out_dir, inventory)

    if args.stdout:
        print(markdown_summary(inventory), end="")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
