#!/usr/bin/env python3
"""Plans and applies recursive submodule fork, remote, and branch setup."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

FORK_REPO_NAME_OVERRIDES = {
    ("p4lang/p4-hlir", "0ab8e58f8a92ee469235028430795088af9cda77"): "p4-hlir-0ab8e58f",
    ("p4lang/p4-hlir", "fdee55e2567fe65463f328d70558b5079894b420"): "p4-hlir-fdee55e2",
    ("p4lang/ptf", "978598dd04434b5270495ac0c6466eb2c6c752f5"): "ptf-978598dd",
    ("p4lang/ptf", "7494366607e2e4c171439df3585eba3c9769fad8"): "ptf-74943666",
}


@dataclass(frozen=True)
class Submodule:
    name: str
    path: str
    url: str
    branch: str | None = None
    depth: int = 0
    head_sha: str | None = None

    @property
    def github_slug(self) -> str | None:
        if self.url.startswith("git@github.com:"):
            slug = self.url.split(":", 1)[1]
        else:
            parsed = urlparse(self.url)
            if parsed.netloc != "github.com":
                return None
            slug = parsed.path.lstrip("/")

        slug = slug.rstrip("/")
        if slug.endswith(".git"):
            slug = slug[:-4]
        return slug or None

    @property
    def repo_name(self) -> str:
        slug = self.github_slug
        return slug.split("/", 1)[1] if slug else Path(self.path).name

    @staticmethod
    def repo_url(account: str, repo_name: str, protocol: str) -> str:
        if protocol == "ssh":
            return f"git@github.com:{account}/{repo_name}.git"
        if protocol == "https":
            return f"https://github.com/{account}/{repo_name}.git"
        raise ValueError(f"unsupported protocol: {protocol}")

    def fork_url(self, account: str, protocol: str, repo_name: str | None = None) -> str | None:
        if not self.github_slug and repo_name is None:
            return None
        return self.repo_url(account, repo_name or self.repo_name, protocol)


def repo_root_from(path: Path) -> Path:
    return path.resolve().parents[2]


def parse_gitmodules_file(gitmodules: Path, prefix: str, depth: int) -> list[Submodule]:
    items: list[Submodule] = []
    current: dict[str, str] | None = None
    for line in gitmodules.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("[submodule "):
            if current:
                rel_path = current["path"]
                full_path = (Path(prefix) / rel_path).as_posix() if prefix else rel_path
                items.append(
                    Submodule(
                        name=current["name"],
                        path=full_path,
                        url=current["url"],
                        branch=current.get("branch"),
                        depth=depth,
                    )
                )
            current = {"name": stripped[len("[submodule "):].rstrip("]").strip('"')}
            continue
        if current and "=" in stripped:
            key, value = [part.strip() for part in stripped.split("=", 1)]
            current[key] = value

    if current:
        rel_path = current["path"]
        full_path = (Path(prefix) / rel_path).as_posix() if prefix else rel_path
        items.append(
            Submodule(
                name=current["name"],
                path=full_path,
                url=current["url"],
                branch=current.get("branch"),
                depth=depth,
            )
        )

    return sorted(items, key=lambda item: item.path)


def collect_submodules(repo_root: Path, recursive: bool) -> list[Submodule]:
    collected: list[Submodule] = []

    def walk(gitmodules: Path, prefix: str, depth: int) -> None:
        items = parse_gitmodules_file(gitmodules, prefix, depth)
        collected.extend(items)
        if not recursive:
            return
        for item in items:
            nested = repo_root / item.path / ".gitmodules"
            if nested.exists():
                walk(nested, item.path, depth + 1)

    walk(repo_root / ".gitmodules", "", 0)
    return sorted(collected, key=lambda item: (item.depth, item.path))


def with_head_shas(repo_root: Path, submodules: list[Submodule]) -> list[Submodule]:
    enriched = []
    for item in submodules:
        head_sha = git(repo_root / item.path, "rev-parse", "HEAD").stdout.strip()
        enriched.append(
            Submodule(
                name=item.name,
                path=item.path,
                url=item.url,
                branch=item.branch,
                depth=item.depth,
                head_sha=head_sha,
            )
        )
    return enriched


def run(command: list[str], dry_run: bool, check: bool = True) -> subprocess.CompletedProcess[str]:
    if dry_run:
        return subprocess.CompletedProcess(command, 0, "", "")
    return subprocess.run(
        command,
        check=check,
        text=True,
        capture_output=True,
    )


def git(path: Path, *args: str, dry_run: bool = False, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", "-C", path.as_posix(), *args], dry_run=dry_run, check=check)


def gh(*args: str, dry_run: bool = False, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["gh", *args], dry_run=dry_run, check=check)


def current_branch(path: Path) -> str:
    return git(path, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()


def local_branch_exists(path: Path, branch: str) -> bool:
    result = git(path, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}", check=False)
    return result.returncode == 0


def remote_url(path: Path, name: str) -> str | None:
    result = git(path, "remote", "get-url", name, check=False)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def create_or_switch_branch(path: Path, branch: str, dry_run: bool) -> str:
    branch_name = current_branch(path)
    if branch_name == branch:
        return "already_on_branch"
    if local_branch_exists(path, branch):
        git(path, "switch", branch, dry_run=dry_run)
        return "switched_existing_branch"
    git(path, "switch", "-c", branch, dry_run=dry_run)
    return "created_branch"


def ensure_remotes(
    path: Path,
    upstream_url: str,
    fork_url: str,
    remote_mode: str,
    dry_run: bool,
) -> str:
    origin = remote_url(path, "origin")
    upstream = remote_url(path, "upstream")
    fork = remote_url(path, "fork")

    if remote_mode == "fork-remote":
        if origin != upstream_url:
            if upstream is None:
                git(path, "remote", "add", "upstream", upstream_url, dry_run=dry_run)
            elif upstream != upstream_url:
                git(path, "remote", "set-url", "upstream", upstream_url, dry_run=dry_run)

        if fork == fork_url:
            return "fork_remote_already_present"
        if fork is None:
            git(path, "remote", "add", "fork", fork_url, dry_run=dry_run)
            return "fork_remote_added"
        git(path, "remote", "set-url", "fork", fork_url, dry_run=dry_run)
        return "fork_remote_updated"

    if remote_mode != "origin-is-fork":
        raise ValueError(f"unsupported remote mode: {remote_mode}")

    if upstream != upstream_url:
        if upstream is None:
            if origin == upstream_url:
                git(path, "remote", "rename", "origin", "upstream", dry_run=dry_run)
            else:
                git(path, "remote", "add", "upstream", upstream_url, dry_run=dry_run)
        else:
            git(path, "remote", "set-url", "upstream", upstream_url, dry_run=dry_run)

    origin = remote_url(path, "origin")
    if origin == fork_url:
        return "origin_already_points_to_fork"
    if origin is None:
        git(path, "remote", "add", "origin", fork_url, dry_run=dry_run)
        return "origin_added_as_fork"
    git(path, "remote", "set-url", "origin", fork_url, dry_run=dry_run)
    return "origin_repointed_to_fork"


def remote_branch_exists(path: Path, remote_name: str, branch: str) -> bool:
    result = git(path, "ls-remote", "--exit-code", "--heads", remote_name, branch, check=False)
    return result.returncode == 0


def push_branch(path: Path, remote_name: str, branch: str, dry_run: bool) -> str:
    if not dry_run:
        before_exists = remote_branch_exists(path, remote_name, branch)
    else:
        before_exists = False
    git(path, "push", "-u", remote_name, f"{branch}:{branch}", dry_run=dry_run)
    return "branch_already_existed" if before_exists else "branch_pushed"


def gh_repo_exists(owner: str, repo_name: str) -> bool:
    result = gh("repo", "view", f"{owner}/{repo_name}", "--json", "name", check=False)
    return result.returncode == 0


def fork_with_gh(upstream_slug: str, owner: str, repo_name: str, dry_run: bool) -> str:
    if not dry_run and gh_repo_exists(owner, repo_name):
        return "fork_already_exists"
    upstream_repo_name = upstream_slug.split("/", 1)[1]
    command = ["repo", "fork", upstream_slug, "--clone=false"]
    if repo_name != upstream_repo_name:
        command.extend(["--fork-name", repo_name])
    gh(*command, dry_run=dry_run)
    return "fork_requested" if dry_run else "fork_created"

def alternate_fork_repo_name(base_repo_name: str, sha: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9._-]+", "-", base_repo_name).strip("-")
    return f"{sanitized}-{sha[:8]}"


def build_plan(submodules: list[Submodule], account: str, fork_protocol: str) -> dict:
    upstream_groups: dict[str, list[Submodule]] = defaultdict(list)
    for item in submodules:
        slug = item.github_slug
        if slug:
            upstream_groups[slug].append(item)

    unique_upstreams = []
    fork_targets_map: dict[tuple[str, str], dict[str, object]] = {}
    path_assignments: dict[str, dict[str, str]] = {}

    for slug, items in sorted(upstream_groups.items()):
        items = sorted(items, key=lambda item: item.path)
        base_repo_name = items[0].repo_name
        upstream_url = items[0].url
        commits: dict[str, list[Submodule]] = defaultdict(list)
        for item in items:
            commits[item.head_sha or "unknown"].append(item)

        ordered_commits = sorted(
            commits.items(),
            key=lambda entry: min(item.path for item in entry[1]),
        )
        canonical_sha = ordered_commits[0][0]
        commit_variants = []

        for sha, sha_items in ordered_commits:
            override_repo_name = FORK_REPO_NAME_OVERRIDES.get((slug, sha))
            if override_repo_name:
                fork_repo_name = override_repo_name
            elif len(ordered_commits) == 1 or sha == canonical_sha:
                fork_repo_name = base_repo_name
            else:
                fork_repo_name = alternate_fork_repo_name(base_repo_name, sha)

            fork_url = Submodule.repo_url(account, fork_repo_name, fork_protocol)
            fork_targets_map[(slug, fork_repo_name)] = {
                "github_slug": slug,
                "repo_name": fork_repo_name,
                "upstream_url": upstream_url,
                "fork_url": fork_url,
                "head_sha": sha,
                "paths": sorted(item.path for item in sha_items),
            }
            commit_variants.append(
                {
                    "head_sha": sha,
                    "fork_repo_name": fork_repo_name,
                    "fork_url": fork_url,
                    "paths": sorted(item.path for item in sha_items),
                }
            )

            for item in sha_items:
                path_assignments[item.path] = {
                    "fork_repo_name": fork_repo_name,
                    "fork_url": fork_url,
                }

        unique_upstreams.append(
            {
                "github_slug": slug,
                "repo_name": base_repo_name,
                "upstream_url": upstream_url,
                "fork_url": Submodule.repo_url(account, base_repo_name, fork_protocol),
                "paths": sorted(item.path for item in items),
                "commit_variants": commit_variants,
            }
        )

    fork_targets = [
        fork_targets_map[key]
        for key in sorted(fork_targets_map)
    ]

    return {
        "top_level_submodule_count": sum(1 for item in submodules if item.depth == 0),
        "submodule_count": len(submodules),
        "github_submodule_count": len(unique_upstreams),
        "fork_target_count": len(fork_targets),
        "duplicate_upstream_count": sum(1 for item in unique_upstreams if len(item["paths"]) > 1),
        "unique_upstreams": unique_upstreams,
        "fork_targets": fork_targets,
        "submodules": [
            {
                "name": item.name,
                "path": item.path,
                "url": item.url,
                "github_slug": item.github_slug,
                "repo_name": item.repo_name,
                "branch": item.branch,
                "depth": item.depth,
                "head_sha": item.head_sha,
                "fork_repo_name": path_assignments[item.path]["fork_repo_name"] if item.github_slug else None,
                "fork_url": path_assignments[item.path]["fork_url"] if item.github_slug else None,
            }
            for item in submodules
        ],
    }


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def summarize(label: str, results: list[dict]) -> str:
    buckets: dict[str, int] = defaultdict(int)
    for item in results:
        buckets[item["status"]] += 1
    ordered = ", ".join(f"{status}={count}" for status, count in sorted(buckets.items()))
    return f"{label}: {ordered}" if ordered else f"{label}: none"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Plan or apply recursive submodule fork, remote, and branch setup."
    )
    parser.add_argument("--account", default="baxia-lan", help="GitHub account that owns the forks.")
    parser.add_argument("--branch", default="codex", help="Branch name to create, switch, or push.")
    parser.add_argument("--recursive", action="store_true", help="Include nested submodules recursively.")
    parser.add_argument(
        "--plan-json",
        default="out/bazel-migration/submodules/fork_plan.json",
        help="Path for the generated plan JSON.",
    )
    parser.add_argument(
        "--result-json",
        default="out/bazel-migration/submodules/fork_apply.json",
        help="Path for the generated apply result JSON.",
    )
    parser.add_argument(
        "--fork-protocol",
        choices=("ssh", "https"),
        default="https",
        help="Protocol used for fork remotes.",
    )
    parser.add_argument(
        "--remote-mode",
        choices=("fork-remote", "origin-is-fork"),
        default="fork-remote",
        help="Whether the fork is added as a side remote or becomes origin.",
    )
    parser.add_argument("--stdout", action="store_true", help="Print a summary to stdout.")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without mutating git state.")
    parser.add_argument(
        "--create-local-branches",
        action="store_true",
        help="Create or switch the requested local branch in each selected submodule.",
    )
    parser.add_argument(
        "--fork-with-gh",
        action="store_true",
        help="Create missing forks with GitHub CLI for each unique upstream repository.",
    )
    parser.add_argument(
        "--setup-remotes",
        action="store_true",
        help="Configure git remotes to reference upstream and fork URLs.",
    )
    parser.add_argument(
        "--push-branch",
        action="store_true",
        help="Push the requested branch to the selected development remote and set upstream tracking.",
    )
    parser.add_argument(
        "--push-remote",
        default="origin",
        help="Remote used by --push-branch. Use origin with origin-is-fork, or fork with fork-remote.",
    )
    args = parser.parse_args()

    repo_root = repo_root_from(Path(__file__))
    submodules = collect_submodules(repo_root, recursive=args.recursive)
    submodules = with_head_shas(repo_root, submodules)
    plan = build_plan(submodules, args.account, args.fork_protocol)
    write_json(repo_root / args.plan_json, plan)
    plan_by_path = {item["path"]: item for item in plan["submodules"]}

    fork_results: list[dict] = []
    branch_results: list[dict] = []
    remote_results: list[dict] = []
    push_results: list[dict] = []

    if args.fork_with_gh:
        for upstream in plan["fork_targets"]:
            try:
                status = fork_with_gh(
                    upstream["github_slug"],
                    args.account,
                    upstream["repo_name"],
                    args.dry_run,
                )
            except subprocess.CalledProcessError as error:
                status = "failed"
                fork_results.append(
                    {
                        "github_slug": upstream["github_slug"],
                        "status": status,
                        "stderr": error.stderr.strip(),
                    }
                )
                continue
            fork_results.append(
                {
                    "github_slug": upstream["github_slug"],
                    "status": status,
                }
            )

    for item in submodules:
        path = repo_root / item.path
        assigned = plan_by_path[item.path]

        if args.create_local_branches:
            try:
                status = create_or_switch_branch(path, args.branch, args.dry_run)
                branch_results.append({"path": item.path, "status": status})
            except subprocess.CalledProcessError as error:
                branch_results.append(
                    {"path": item.path, "status": "failed", "stderr": error.stderr.strip()}
                )

        if args.setup_remotes:
            fork_url = assigned["fork_url"]
            if not fork_url:
                remote_results.append({"path": item.path, "status": "skipped_non_github"})
            else:
                try:
                    status = ensure_remotes(
                        path,
                        item.url,
                        fork_url,
                        args.remote_mode,
                        args.dry_run,
                    )
                    remote_results.append({"path": item.path, "status": status})
                except subprocess.CalledProcessError as error:
                    remote_results.append(
                        {"path": item.path, "status": "failed", "stderr": error.stderr.strip()}
                    )

        if args.push_branch:
            try:
                status = push_branch(path, args.push_remote, args.branch, args.dry_run)
                push_results.append({"path": item.path, "status": status})
            except subprocess.CalledProcessError as error:
                push_results.append(
                    {"path": item.path, "status": "failed", "stderr": error.stderr.strip()}
                )

    result = {
        "plan": plan,
        "fork_results": fork_results,
        "branch_results": branch_results,
        "remote_results": remote_results,
        "push_results": push_results,
    }
    write_json(repo_root / args.result_json, result)

    if args.stdout:
        scope = "Recursive submodules" if args.recursive else "Top-level submodules"
        print(f"{scope}: {plan['submodule_count']} (top-level={plan['top_level_submodule_count']})")
        print(f"Unique upstream repos: {plan['github_submodule_count']}")
        print(f"Fork targets: {plan['fork_target_count']}")
        print(f"Duplicate upstream repos: {plan['duplicate_upstream_count']}")
        if branch_results:
            print(summarize("Branch results", branch_results))
        if remote_results:
            print(summarize("Remote results", remote_results))
        if push_results:
            print(summarize("Push results", push_results))
        if fork_results:
            print(summarize("Fork results", fork_results))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
