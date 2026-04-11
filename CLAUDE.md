# CLAUDE.md — SONiC Buildimage Agent Rules

## Project Goal
Migrate this repo from GNU Make → Bazel (bzlmod), fully hermetic.
Based on Aspect's work: https://github.com/thesayyn/sonic-buildimage

## Acceptance Gates (hard fail — no workarounds)

### Gate 1: docker-sonic-vs.gz
```
bazel test //acceptance:vs_pytest --sandbox_default_allow_network=false
```
- Builds docker-sonic-vs.gz with Bazel (replaces `make target/docker-sonic-vs.gz`)
- All dependency packages built with Bazel, fully hermetic
- Loads image, boots container, all 40+ services start
- sonic-swss full pytest suite passes
- Each dependency package has its own `bazel test` target that passes

### Gate 2: Cloud Build CI
```
bazel test //acceptance:cloud_build
```
- Cloud Build triggers on push, runs full build + test
- Remote cache hit rate >= 80% on second build
- Logs visible on GitHub (commit status or artifact)
- Remote execution analyzed and implemented if feasible

### Gate 3: sonic-broadcom.bin
```
bazel test //acceptance:broadcom_bin --sandbox_default_allow_network=false
```
- Builds sonic-broadcom.bin with Bazel (replaces `make target/sonic-broadcom.bin`)
- Kernel built hermetically (no apt-get during build)
- All dependency packages built with Bazel, fully hermetic
- Output < 400 MB
- Each dependency package has its own `bazel test` target that passes

### Gate 4: sonic-alpinevs.img.gz
```
bazel test //acceptance:alpinevs --sandbox_default_allow_network=false
```
- Builds sonic-alpinevs.img.gz with Bazel (replaces `make target/sonic-alpinevs.img.gz`)
- All dependency packages built with Bazel, fully hermetic
- alpinevs tests pass
- Each dependency package has its own `bazel test` target that passes

## Hermeticity — Non-Negotiable

These are enforced, not documented:
- `--sandbox_default_allow_network=false` in `.bazelrc` (default, not optional)
- NO `no-sandbox` tag on any genrule. If a genrule needs network, it's wrong.
- Network access only in `repository_rule`s, never in build actions
- All external downloads pinned with `sha256`
- `SOURCE_DATE_EPOCH=0` on all packaging actions
- NO `continue-on-error` in CI. Failure is failure.

## Bazel Conventions
- bzlmod only — `MODULE.bazel`, no `WORKSPACE`
- All BUILD files formatted with `buildifier` before committing
- Target names: `lower_snake_case`
- Base image digests pinned by `sha256`
- Never use `glob()` when files can be listed explicitly
- `select()` expressions go at the bottom of the target

## Submodule Rules
- Use `rules_foreign_cc` (`configure_make()`) for submodules with autotools
- Use native `cc_library` only when the submodule has no existing build system
- If a submodule uses Bazel internally, depend on its targets directly
- Never run `git submodule update` inside a build action

## Migration Rules
- Migrate one package at a time; verify before moving on
- Dependency order: leaves first → libswsscommon → services → images
- Never delete a `.mk` file until Bazel equivalent passes debdiff + tests
- Make system stays functional during transition
- When Make and Bazel disagree, Make is ground truth

## Verification (every package, before moving to next)
- [ ] `bazel build` succeeds with `--sandbox_default_allow_network=false`
- [ ] `bazel test` for the package passes
- [ ] `debdiff make.deb bazel.deb` — timestamps only
- [ ] Two clean builds produce identical sha256
- [ ] No `no-sandbox` tag anywhere

## Commit Format
```
<type>(<scope>): <subject>
type:  feat | fix | refactor | build | ci | docs | test | chore
scope: bazel | deb | oci | onie | platform/<name> | rules | ci
```

## Size Budgets
| Artifact | Limit |
|---|---|
| `sonic-broadcom.bin` | 400 MB |
| Any single service OCI image | 300 MB |
| `sonic-common-layer` (shared base) | 150 MB |
