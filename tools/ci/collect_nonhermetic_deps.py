#!/usr/bin/env python3
"""Scans the repo for non-hermetic build and image assembly inputs."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Issue:
    path: str
    line: int
    severity: str
    category: str
    detail: str
    fix: str


PATTERNS = (
    (
        re.compile(r"\b(?:apt-get|apt)\b.*\binstall\b", re.IGNORECASE),
        "MEDIUM",
        "apt_install",
        "apt install in build step (network at execution time)",
        "Move package resolution to pinned repository inputs or prebuilt base artifacts.",
    ),
    (
        re.compile(r"\bpip(?:3)?\s+install\b.*git\+https://", re.IGNORECASE),
        "HIGH",
        "pip_git",
        "pip install from git+https at execution time",
        "Vendor the wheel or lock it through repository-time dependency resolution.",
    ),
    (
        re.compile(r"\bpip(?:3)?\s+install\b", re.IGNORECASE),
        "MEDIUM",
        "pip_install",
        "pip install in build step (network at execution time)",
        "Resolve Python dependencies through a lockfile and repository fetch phase.",
    ),
    (
        re.compile(r"\bwget\b.*https?://", re.IGNORECASE),
        "HIGH",
        "wget",
        "wget download from the public network",
        "Replace with a pinned repository fetch such as http_file/http_archive.",
    ),
    (
        re.compile(r"\bcurl\b.*https?://", re.IGNORECASE),
        "HIGH",
        "curl",
        "curl download from the public network",
        "Replace with a pinned repository fetch such as http_file/http_archive.",
    ),
    (
        re.compile(r"\bgit\s+clone\b.*https?://", re.IGNORECASE),
        "HIGH",
        "git_clone",
        "git clone at build time",
        "Replace with a pinned repository rule or vendored source tarball.",
    ),
    (
        re.compile(r"\bcargo\s+install\b", re.IGNORECASE),
        "HIGH",
        "cargo_install",
        "cargo install at build time",
        "Use a pinned Rust dependency graph and repository-time vendoring.",
    ),
    (
        re.compile(r"YourPaSsWoRd"),
        "HIGH",
        "default_password",
        "plaintext default password committed to source",
        "Move secrets to runtime or CI secret injection, not source control.",
    ),
    (
        re.compile(r"trafficmanager\.net|azurecr\.io", re.IGNORECASE),
        "MEDIUM",
        "hardcoded_external_endpoint",
        "hardcoded external mirror or registry endpoint",
        "Inject the endpoint through Bazel/CI configuration instead of hardcoding it.",
    ),
)

SCAN_ROOTS = (
    "sonic-slave-bookworm",
    "dockers",
    "scripts",
    "tools/bazel",
    "rules/config",
)

DOCKERFILE_NAMES = ("Dockerfile", "Dockerfile.j2", "Dockerfile.user")


def repo_root_from(path: Path) -> Path:
    return path.resolve().parents[2]


def iter_scan_files(repo_root: Path) -> Iterable[Path]:
    for entry in SCAN_ROOTS:
        path = repo_root / entry
        if not path.exists():
            continue
        if path.is_file():
            yield path
            continue
        if path.name.startswith("sonic-slave-"):
            for child in path.rglob("*"):
                if child.is_file() and child.name in DOCKERFILE_NAMES:
                    yield child
            continue
        for child in path.rglob("*"):
            if not child.is_file():
                continue
            if child.name in DOCKERFILE_NAMES or child.suffix in {".sh", ".mk", ".j2"}:
                yield child


def iter_issues(repo_root: Path) -> list[Issue]:
    issues: list[Issue] = []
    seen: set[tuple[str, int, str, str]] = set()
    for path in sorted(iter_scan_files(repo_root)):
        rel_path = path.relative_to(repo_root).as_posix()
        try:
            lines = path.read_text(errors="ignore").splitlines()
        except OSError:
            continue
        for line_number, raw_line in enumerate(lines, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            for pattern, severity, category, detail, fix in PATTERNS:
                if not pattern.search(line):
                    continue
                key = (rel_path, line_number, category, detail)
                if key in seen:
                    continue
                seen.add(key)
                issues.append(
                    Issue(
                        path=rel_path,
                        line=line_number,
                        severity=severity,
                        category=category,
                        detail=detail,
                        fix=fix,
                    ),
                )
    return issues


def markdown_report(payload: dict) -> str:
    lines = [
        "# SONiC Non-Hermetic Build Audit",
        "",
        f"Generated: {payload['generated_at_utc']}",
        "",
        "## Summary",
        "",
        f"- Total issues: **{payload['summary']['total']}**",
        f"- HIGH: **{payload['summary']['by_severity'].get('HIGH', 0)}**",
        f"- MEDIUM: **{payload['summary']['by_severity'].get('MEDIUM', 0)}**",
        f"- LOW: **{payload['summary']['by_severity'].get('LOW', 0)}**",
        "",
        "## Issues",
        "",
        "| Severity | File | Line | Category | Detail | Fix |",
        "|----------|------|------|----------|--------|-----|",
    ]
    for issue in payload["issues"]:
        lines.append(
            f"| {issue['severity']} | `{issue['path']}` | {issue['line']} | "
            f"`{issue['category']}` | {issue['detail']} | {issue['fix']} |"
        )
    if not payload["issues"]:
        lines.append("| NONE | n/a | n/a | n/a | No matching issues found | n/a |")
    return "\n".join(lines) + "\n"


def build_payload(repo_root: Path) -> dict:
    issues = [asdict(issue) for issue in iter_issues(repo_root)]
    by_severity = Counter(issue["severity"] for issue in issues)
    by_category = Counter(issue["category"] for issue in issues)
    return {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repo_root": repo_root.as_posix(),
        "summary": {
            "total": len(issues),
            "by_severity": dict(sorted(by_severity.items())),
            "by_category": dict(sorted(by_category.items())),
        },
        "issues": issues,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--format",
        choices=("json", "markdown"),
        default="markdown",
        help="Output format.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional path to write the report to.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_from(Path(__file__))
    payload = build_payload(repo_root)
    rendered = (
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
        if args.format == "json"
        else markdown_report(payload)
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
