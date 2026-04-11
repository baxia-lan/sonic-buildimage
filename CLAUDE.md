# CLAUDE.md — SONiC Buildimage Agent Rules

Treat this file as an execution protocol, not advisory guidance.
If behavior and this document conflict, follow the document.
During any `compact`, preserve and carry forward all rules.

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
- Each dependency package has its own `bazel test` target that passes

### Gate 4: sonic-alpinevs.img.gz
```
bazel test //acceptance:alpinevs --sandbox_default_allow_network=false
```
- Builds sonic-alpinevs.img.gz with Bazel (replaces `make target/sonic-alpinevs.img.gz`)
- All dependency packages built with Bazel, fully hermetic
- alpinevs tests pass
- Each dependency package has its own `bazel test` target that passes

## Execution Protocol

### Stopping Rules
Stopping execution requires an explicit reason. Valid reasons:
- `missing_permissions` or `missing_credentials`
- `destructive_action_requires_approval`
- `conflicting_requirements`
- `would_require_guessing`

These are NEVER valid stop reasons:
- "A subtask completed"
- "CI is running"
- "Tests passed"
- "An artifact was generated"
- "This feels like a good handoff point"

If no valid stop reason applies, continue executing.

### After Every Completed Subgoal
Record all of the following before deciding whether to stop:
- `current_dominant_blocker`: what is the single thing preventing progress?
- `highest_value_next_action`: what is the most impactful thing to do right now?
- `what_can_break`: what assumptions are untested?
- `what_can_run_in_parallel`: what independent work can subagents do?

If `highest_value_next_action` is non-empty and no valid stop reason exists,
take that action immediately. Do not summarize and stop.

### Verification After Every Change
After every code change:
1. Rerun the most direct end-to-end check immediately
2. Do not commit until the check passes
3. "Analysis passes" (`--nobuild`) does NOT count as verification
4. Must have runtime evidence: actual build output, actual test result, actual file content
5. If verification fails, fix and re-verify before moving on

### No Fake Completion
- No `continue-on-error` in CI. Failure is failure.
- No stubs, mocks, or canned outputs to simulate completion.
- No marking tasks "done" without runtime evidence.
- "Code written" is not "task done". Done requires: implementation + integration + verification + next-step exhaustion.
- State exactly what was verified and what was not.
- If something is unverified, say so plainly. Do not hide uncertainty.

## Subagent Management

### Delegation
- Decompose work and spawn subagents for bounded, parallelizable subtasks.
- Give each subagent concrete scope, explicit ownership, and clear output.
- Prefer disjoint write scopes so parallel work does not conflict.
- The main agent owns plan, sequencing, delegation, integration, verification, and final acceptance.
- Subagents assist with execution; they do not decide that work is finished.

### Reviewing Subagent Output
- Read the actual diffs, not just the summary.
- Rerun or extend verification. Do not accept "should work" as evidence.
- Require evidence: changed files, checks run, known limitations.
- Reject work that is hacked together, mocked out, or presented as complete without real support.
- The main agent must personally inspect delegated diffs and rerun critical checks.

## Hermeticity — Non-Negotiable

These are enforced, not documented:
- `--sandbox_default_allow_network=false` in `.bazelrc` (default, not optional)
- NO `no-sandbox` tag on any genrule. If a genrule needs network, it's wrong.
- Network access only in `repository_rule`s, never in build actions
- All external downloads pinned with `sha256`
- `SOURCE_DATE_EPOCH=0` on all packaging actions

## Bazel Conventions
- bzlmod only — `MODULE.bazel`, no `WORKSPACE`
- All BUILD files formatted with `buildifier` before committing
- Target names: `lower_snake_case`
- Base image digests pinned by `sha256`
- Never use `glob()` when files can be listed explicitly
- `select()` expressions go at the bottom of the target

## Submodule Build Rules
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

## Git Safety
- Never rewrite git history
- Never use `git push --force`, `git rebase`, `git reset --hard`, `git commit --amend`
- Prefer additive follow-up commits over rewriting

## Commit Format
```
<type>(<scope>): <subject>
type:  feat | fix | refactor | build | ci | docs | test | chore
scope: bazel | deb | oci | onie | platform/<name> | rules | ci
```
