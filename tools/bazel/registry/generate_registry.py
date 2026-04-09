#!/usr/bin/env python3
"""Generate a local Bazel registry from submodules in src/.

Scans src/ for directories containing a MODULE.bazel file and creates a
Bazel registry structure under tools/bazel/registry/ that maps each
submodule as a local_path module. This lets the root MODULE.bazel depend
on submodule targets via bazel_dep() without hitting the WORKSPACE
boundary problem.

Registry layout produced:
  tools/bazel/registry/
    bazel_registry.json
    modules/
      <module_name>/
        metadata.json
        <version>/
          MODULE.bazel  (symlink to src/<submodule>/MODULE.bazel)
          source.json   (type: local_path)

Usage:
  python3 tools/bazel/registry/generate_registry.py
"""

import json
import os
import re
import sys
from pathlib import Path


def find_repo_root():
    """Walk up from this script's location to find the repo root (contains MODULE.bazel)."""
    candidate = Path(__file__).resolve().parent
    for _ in range(10):
        if (candidate / "MODULE.bazel").exists() and (candidate / "src").is_dir():
            return candidate
        candidate = candidate.parent
    print("ERROR: could not find repo root", file=sys.stderr)
    sys.exit(1)


def parse_module_bazel(path):
    """Extract module name and version from a MODULE.bazel file."""
    text = path.read_text()
    name_match = re.search(r'module\s*\(\s*name\s*=\s*"([^"]+)"', text)
    version_match = re.search(r'version\s*=\s*"([^"]+)"', text)
    if not name_match:
        return None, None
    name = name_match.group(1)
    version = version_match.group(1) if version_match else "0.0.0"
    return name, version


def generate_registry(repo_root):
    """Scan src/ and generate the local registry."""
    src_dir = repo_root / "src"
    registry_dir = repo_root / "tools" / "bazel" / "registry"
    modules_dir = registry_dir / "modules"

    discovered = []

    for entry in sorted(src_dir.iterdir()):
        if not entry.is_dir():
            continue
        module_bazel = entry / "MODULE.bazel"
        if not module_bazel.exists():
            continue

        name, version = parse_module_bazel(module_bazel)
        if not name:
            print(f"  SKIP {entry.name}: could not parse module name", file=sys.stderr)
            continue

        print(f"  {entry.name} -> {name}@{version}")
        discovered.append((entry, name, version))

    if not discovered:
        print("No submodules with MODULE.bazel found in src/.", file=sys.stderr)
        return

    # Create bazel_registry.json
    # module_base_path is relative to the registry directory itself.
    # Since the registry lives at tools/bazel/registry/, we need "../../.."
    # to get back to the repo root where source.json paths are rooted.
    rel_base = os.path.relpath(repo_root, registry_dir)
    registry_json = {
        "module_base_path": rel_base,
        "mirrors": [],
    }
    (registry_dir / "bazel_registry.json").write_text(
        json.dumps(registry_json, indent=2) + "\n"
    )

    for submodule_path, name, version in discovered:
        mod_dir = modules_dir / name
        ver_dir = mod_dir / version
        ver_dir.mkdir(parents=True, exist_ok=True)

        # metadata.json
        metadata = {
            "homepage": "",
            "maintainers": [],
            "versions": [version],
            "yanked_versions": {},
        }
        (mod_dir / "metadata.json").write_text(
            json.dumps(metadata, indent=2) + "\n"
        )

        # source.json — local_path relative from module_base_path
        rel_path = os.path.relpath(submodule_path, repo_root)
        source = {
            "type": "local_path",
            "path": rel_path,
        }
        (ver_dir / "source.json").write_text(
            json.dumps(source, indent=2) + "\n"
        )

        # MODULE.bazel — symlink to the submodule's MODULE.bazel
        symlink_target = ver_dir / "MODULE.bazel"
        if symlink_target.exists() or symlink_target.is_symlink():
            symlink_target.unlink()
        # Use relative symlink so it works if the repo is moved
        rel_module = os.path.relpath(
            submodule_path / "MODULE.bazel", ver_dir
        )
        symlink_target.symlink_to(rel_module)

    print(f"\nGenerated registry with {len(discovered)} module(s) at:")
    print(f"  {registry_dir}")
    print(f"\nRegistered modules:")
    for _, name, version in discovered:
        print(f"  {name} @ {version}")


def main():
    repo_root = find_repo_root()
    print(f"Repo root: {repo_root}")
    print(f"Scanning src/ for MODULE.bazel files...\n")
    generate_registry(repo_root)


if __name__ == "__main__":
    main()
