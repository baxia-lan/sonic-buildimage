# CLAUDE.md — SONiC Buildimage Agent Rules

Full migration plan: `docs/MIGRATION_PLAN.md`

## Project Goal
Migrate this repo from GNU Make → Bazel (bzlmod). Three phases:
1. Make → Bazel (all artifacts: .deb, .whl, OCI images, ONIE .bin)
2. Collapse 5-deep Docker layer chain → 2 layers per service image
3. Trim `sonic-broadcom.bin` from ~1 GB → < 400 MB

## Repo Orientation
- `slave.mk` — core build rules (1,908 lines); reference for what Bazel must replicate
- `rules/*.mk` — 327 per-artifact build recipes
- `dockers/` — 58 Jinja2 Dockerfile templates
- `src/` — 48 git submodules (each needs a `BUILD.bazel`)
- `platform/` — 25 platforms; `broadcom/one-image.mk` is the ONIE image recipe
- `docs/MIGRATION_PLAN.md` — detailed phase plans, week-by-week schedule

## Bazel Conventions
- bzlmod only — `MODULE.bazel`, no `WORKSPACE`
- All BUILD files formatted with `buildifier` before committing
- Target names: `lower_snake_case`
- Base image digests must be pinned by `sha256`, never by mutable tag
- Never use `glob()` when files can be listed explicitly
- `select()` expressions go at the bottom of the target

## Hermeticity — Non-Negotiable
- `--incompatible_strict_action_env=true` always on
- `--sandbox_default_allow_network=false` always on
- Network access only in `repository_rule`s, never in build actions
- All external tarballs pinned with `sha256`
- `SOURCE_DATE_EPOCH=0` on all packaging actions

## Migration Rules
- Migrate one package or image at a time; verify before moving on
- Never delete a `.mk` file until the Bazel equivalent is verified end-to-end in CI
- Make system stays functional and authoritative during the entire transition
- Dependency order: leaves first (libnl, libhiredis) → libswsscommon → services → images
- Output equivalence required: Bazel-produced `.deb` must pass `debdiff` against the Make-produced one before the `.mk` is retired
- When Make and Bazel outputs disagree, treat Make as ground truth — fix Bazel, never patch Make to match

## Submodule Rules
- Each `src/<submodule>` gets its own `BUILD.bazel`; never reference submodule files from a parent `BUILD.bazel` directly
- Use `rules_foreign_cc` (`cmake()`, `configure_make()`) for submodules with CMake/autotools; use native `cc_library` only when the submodule has no existing build system
- Never run `git submodule update` inside a build action — submodule state must be pinned before `bazel build` is invoked
- If a submodule already uses Bazel internally (e.g. `sonic-pins`), depend on its targets directly; do not wrap it in `rules_foreign_cc`

## Code Rules
- Read a file before editing it
- Verify every change builds successfully before marking it done
- No speculative abstractions — build only what the current task requires
- No comments unless the logic is non-obvious
- Document every removed dependency in `docs/removed_deps.md`

## Commit Format
```
<type>(<scope>): <subject>
type:  feat | fix | refactor | build | ci | docs | test | chore
scope: bazel | deb | oci | onie | platform/<name> | rules | ci
```

## Size Budgets (hard limits — fail the PR if exceeded)
| Artifact | Limit |
|---|---|
| `sonic-broadcom.bin` | 400 MB |
| Any single service OCI image | 300 MB |
| `sonic-common-layer` (shared base) | 150 MB |
| Any `.deb` size regression vs Make baseline | 0 MB (must not grow) |

## Verification Checklist (before any PR)
- [ ] `bazel build //path/to:target` succeeds with `--sandbox_debug`, no warnings
- [ ] `debdiff make_output.deb bazel_output.deb` shows no meaningful diff (timestamps only)
- [ ] Build is reproducible: two clean builds produce bit-identical output
- [ ] OCI image has ≤ 3 layers (`docker inspect … | jq '.[0].RootFS.Layers|length'`)
- [ ] Artifact is within size budget (see above)
- [ ] Cloud Build passes and remote cache hit rate ≥ 80% on re-run

## Ultimate Verification: docker-sonic-vs pytest
The definitive test that Bazel build artifacts are correct is:
1. `bazel build //platform/vs:docker_sonic_vs` produces a hermetic docker-sonic-vs image
2. Load the image: `docker load < bazel-bin/platform/vs/docker_sonic_vs/tarball.tar`
3. Tag it: `docker tag <sha> docker-sonic-vs:latest`
4. Run sonic-swss pytest against it:
   ```
   cd src/sonic-swss/tests
   sudo pytest --imgname=docker-sonic-vs:latest -v test_port.py
   ```
5. All pytest tests pass — this proves orchagent, syncd-vs, redis, swss-common,
   FRR, supervisord, config generation, and all 40+ services work correctly.

This is the ONLY verification that matters for declaring the migration complete.
Everything else (debdiff, size budgets, reproducibility) is secondary to this.
