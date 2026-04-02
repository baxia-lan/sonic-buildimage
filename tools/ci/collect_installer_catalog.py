#!/usr/bin/env python3
"""Collects SONiC platform and installer metadata from Bazel lock files."""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_LABELS = ("//platforms/...", "//installers/...")
EXPECTED_PLATFORM_LABELS = {
    "//platforms/alpinevs:platform",
    "//platforms/aspeed:platform",
    "//platforms/broadcom:platform",
    "//platforms/centec:platform",
    "//platforms/centec-arm64:platform",
    "//platforms/clounix:platform",
    "//platforms/generic:platform",
    "//platforms/marvell-prestera:platform",
    "//platforms/marvell-teralynx:platform",
    "//platforms/mellanox:platform",
    "//platforms/nephos:platform",
    "//platforms/nokia-vs:platform",
    "//platforms/vpp:platform",
    "//platforms/vs:platform",
}
EXPECTED_INSTALLER_LABELS = {
    "//installers/alpinevs:kvm",
    "//installers/alpinevs:onie",
    "//installers/alpinevs:raw",
    "//installers/aspeed:onie",
    "//installers/broadcom:aboot",
    "//installers/broadcom:onie",
    "//installers/broadcom:raw",
    "//installers/centec:onie",
    "//installers/centec-arm64:onie",
    "//installers/clounix:onie",
    "//installers/generic:aboot",
    "//installers/generic:onie",
    "//installers/marvell-prestera:onie",
    "//installers/marvell-teralynx:onie",
    "//installers/mellanox:onie",
    "//installers/nephos:onie",
    "//installers/nokia-vs:onie",
    "//installers/vpp:kvm",
    "//installers/vpp:onie",
    "//installers/vpp:raw",
    "//installers/vs:kvm",
    "//installers/vs:onie",
    "//installers/vs:raw",
}
VALID_INSTALLER_FORMATS = {"onie", "raw", "aboot", "kvm"}


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


def load_lock_registry(paths: list[Path]) -> dict[str, dict]:
    registry = {}
    for path in paths:
        if not path.name.endswith(".lock.json"):
            continue
        payload = json.loads(path.read_text())
        payload["label"] = payload["label"].lstrip("@")
        direct = payload.get("direct_dependencies", {})
        for key in ("build", "runtime", "python_wheels", "fragments", "sources"):
            direct[key] = [item.lstrip("@") for item in direct.get(key, [])]
        if direct.get("base"):
            direct["base"] = direct["base"].lstrip("@")
        registry[payload["label"]] = payload
    return registry


def markdown_report(payload: dict) -> str:
    lines = [
        "# SONiC Installer Catalog",
        "",
        f"Generated: {payload['generated_at_utc']}",
        "",
        "## Summary",
        "",
        f"- platform_targets: {payload['summary']['platform_targets']}",
        f"- installer_targets: {payload['summary']['installer_targets']}",
        "",
        "## Installer Formats",
        "",
    ]
    for fmt, count in sorted(payload["summary"]["installer_formats"].items()):
        lines.append(f"- {fmt}: {count}")
    lines.append("")

    if payload["validation_errors"]:
        lines.extend([
            "## Validation Errors",
            "",
        ])
        for error in payload["validation_errors"]:
            lines.append(f"- {error}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect SONiC installer and platform migration metadata.")
    parser.add_argument("labels", nargs="*", default=list(DEFAULT_LABELS))
    parser.add_argument("--out-dir", default="out/bazel-migration/installer-catalog")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    repo_root = repo_root_from(Path(__file__))
    bazel = str(repo_root / "tools/bazel/bazelw")

    build_if_needed(repo_root, bazel, list(args.labels), args.skip_build)
    output_paths = cquery_output_paths(repo_root, bazel, list(args.labels))
    registry = load_lock_registry(output_paths)

    platforms = {
        label: lock
        for label, lock in registry.items()
        if lock["artifact_kind"] == "platform"
    }
    installers = {
        label: lock
        for label, lock in registry.items()
        if lock["artifact_kind"] == "host_image"
    }

    errors = []
    expect_full_platform_matrix = "//platforms/..." in args.labels
    expect_full_installer_matrix = "//installers/..." in args.labels

    missing_platforms = sorted((EXPECTED_PLATFORM_LABELS if expect_full_platform_matrix else set()) - set(platforms))
    missing_installers = sorted((EXPECTED_INSTALLER_LABELS if expect_full_installer_matrix else set()) - set(installers))
    for label in missing_platforms:
        errors.append(f"Missing platform target {label}")
    for label in missing_installers:
        errors.append(f"Missing installer target {label}")

    installer_formats = Counter()
    for label, lock in sorted(installers.items()):
        fmt = lock.get("installer", {}).get("format")
        if fmt not in VALID_INSTALLER_FORMATS:
            errors.append(f"{label}: invalid installer format {fmt!r}")
            continue
        installer_formats[fmt] += 1

        fragments = lock.get("direct_dependencies", {}).get("fragments", [])
        if len(fragments) != 1:
            errors.append(f"{label}: expected exactly one platform fragment, got {len(fragments)}")
            continue
        if fragments[0] not in EXPECTED_PLATFORM_LABELS:
            errors.append(f"{label}: unexpected platform fragment {fragments[0]}")

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "labels": list(args.labels),
        "summary": {
            "platform_targets": len(platforms),
            "installer_targets": len(installers),
            "installer_formats": dict(sorted(installer_formats.items())),
        },
        "platforms": dict(sorted(platforms.items())),
        "installers": dict(sorted(installers.items())),
        "validation_errors": errors,
    }

    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "installer_catalog.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    (out_dir / "installer_catalog.md").write_text(markdown_report(payload))

    if args.stdout:
        print(markdown_report(payload), end="")
    if errors:
        for error in errors:
            print(error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
