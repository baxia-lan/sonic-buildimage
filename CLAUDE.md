# CLAUDE.md — SONiC Buildimage Make → Bazel Execution Protocol

Treat this file as a repo-specific execution protocol, not advisory guidance.

Within platform policy, tool limits, and the user's explicit request, follow this
document strictly. If context is compacted or reset, preserve these rules and
restore the active execution state before taking the next step.

---

## 1) Compact / Context Carry-Forward Rules

During any `compact`, preserve in this priority order:

1. This file and all active project CLAUDE/rules/skills constraints
2. The current requested objective and its scope boundary
3. Architecture decisions and design rationale
4. Modified files and their key changes
5. Verification evidence: commands run, pass/fail, key outputs
6. Current dominant blocker and highest-value next action
7. Open TODOs, known issues, rollback notes
8. Parallelizable work that can be delegated safely
9. Tool output details may be dropped, but keep outcome/evidence

Never silently weaken, summarize away, or reinterpret development principles.

After any compact or context reset, restore and continue from this execution
state:

- `requested_objective`
- `scope_boundary`
- `current_dominant_blocker`
- `highest_value_next_action`
- `what_can_break`
- `what_can_run_in_parallel`
- `modified_files`
- `verification_evidence`
- `open_todos`

---

## 2) Project Goal

Migrate this repository from GNU Make to Bazel (`bzlmod`), with fully hermetic
builds where feasible and honest evidence where not yet complete.

Reference implementation:
- Aspect-based prior work may be used as a reference:
  `https://github.com/thesayyn/sonic-buildimage`

However:
- The current repository behavior remains ground truth during migration.
- If Make and Bazel disagree, diagnose the difference; do not paper over it.
- This work is intended to remain upstreamable.
- Therefore the default posture is **coexistence**: add Bazel while preserving the
  original Make rules and Make-driven build graph.

---

## 3) Final Acceptance Gates (hard fail, no workarounds)

These are repo-level acceptance gates. Do **not** claim the migration complete
until the relevant gate passes with runtime evidence.

Passing these gates does **not** authorize deleting the original Make system.
Repo completion for this upstream-oriented migration means Bazel works **while**
the original Make rules still remain present and functional unless the user
creates a separate cleanup-only objective.

### Gate 1: `docker-sonic-vs.gz`
```bash
bazel test //acceptance:vs_pytest --sandbox_default_allow_network=false
```

Required:
- Builds `docker-sonic-vs.gz` with Bazel
- Replaces `make target/docker-sonic-vs.gz` behaviorally
- All dependency packages are built with Bazel, fully hermetic
- Image loads and boots successfully
- All 40+ services start
- `sonic-swss` full pytest suite passes
- Each dependency package has its own `bazel test` target and it passes

### Gate 2: Cloud Build CI
```bash
bazel test //acceptance:cloud_build
```

Required:
- Cloud Build triggers on push
- Full build + test run in CI
- Remote cache hit rate >= 80% on second build
- Logs visible on GitHub as status, artifact, or equivalent evidence
- Remote execution analyzed and implemented if feasible

### Gate 3: `sonic-broadcom.bin`
```bash
bazel test //acceptance:broadcom_bin --sandbox_default_allow_network=false
```

Required:
- Builds `sonic-broadcom.bin` with Bazel
- Replaces `make target/sonic-broadcom.bin` behaviorally
- Kernel built hermetically
- No `apt-get` or equivalent networked package install during build actions
- All dependency packages are built with Bazel, fully hermetic
- Each dependency package has its own `bazel test` target and it passes

### Gate 4: `sonic-alpinevs.img.gz`
```bash
bazel test //acceptance:alpinevs --sandbox_default_allow_network=false
```

Required:
- Builds `sonic-alpinevs.img.gz` with Bazel
- Replaces `make target/sonic-alpinevs.img.gz` behaviorally
- All dependency packages are built with Bazel, fully hermetic
- `alpinevs` tests pass
- Each dependency package has its own `bazel test` target and it passes

---

## 4) Non-Negotiable Engineering Invariants

### 4.1 Hermeticity
These are enforced constraints, not suggestions:

- `--sandbox_default_allow_network=false` in `.bazelrc` by default
- No `no-sandbox` tag on any `genrule`
- Network access only in `repository_rule`s, never in build actions
- All external downloads pinned with `sha256`
- `SOURCE_DATE_EPOCH=0` on all packaging actions
- No `apt-get`, `apk add`, `yum`, `dnf`, or equivalent package-manager access in build actions
- No `git submodule update` inside build actions

### 4.2 Ground Truth During Migration
- The Make system stays functional during transition
- Migrate one package or one build boundary at a time
- When Make and Bazel disagree, Make is ground truth until parity is proven
- Never delete, rename, or semantically weaken upstream Make rules as part of the Bazel migration
- Never delete a `.mk`, `Makefile`, or related Make helper path in normal migration work
- Never edit generated output under `target/` as a substitute for fixing build logic

### 4.3 Upstreamability
- Assume the end state must be acceptable for upstream review
- Prefer additive Bazel changes over Make replacement
- Keep Bazel and Make ownership explicit
- Report what remains Make-owned after every migration unit
- If a future cleanup/removal wave is ever desired, treat it as a separate objective with separate review

### 4.4 No Fake Completion
- No `continue-on-error` in CI
- No stubs, mocks, or canned outputs to simulate completion
- No marking work "done" without runtime evidence
- "Code written" is not "task done"
- Done requires: implementation + integration + verification + next-step exhaustion
- If something is unverified, say so plainly

### 4.5 Git Safety
- Never rewrite git history
- Never use:
  - `git push --force`
  - `git rebase`
  - `git reset --hard`
  - `git commit --amend`
- Prefer additive follow-up commits

---

## 5) Task Boundary and Completion Rules

### 5.1 Scope Discipline
The agent must optimize for the **current requested objective**, not for
unbounded repo-wide cleanup.

Do not expand scope just because more work is possible.

Valid examples of staying in scope:
- Migrating one package
- Fixing the directly blocking dependency for that package
- Adding the narrowest verification needed for that package
- Fixing a directly affected Bazel/package/image integration issue
- Preserving or clarifying the Make path while adding Bazel

Invalid scope expansion:
- Opportunistic unrelated refactors
- Broad repo cleanup not required for the current objective
- Starting the next migration unit before the current one is verified or explicitly deferred
- Removing Make rules because Bazel now works for one path

### 5.2 Valid Reasons to Stop
Stopping requires an explicit reason. Valid stop reasons are:

- `requested_objective_completed`
- `missing_permissions`
- `missing_credentials`
- `destructive_action_requires_approval`
- `conflicting_requirements`
- `would_require_guessing`

These are **not** valid stop reasons:
- "A subtask completed"
- "CI is running"
- "Tests passed"
- "An artifact was generated"
- "This feels like a good handoff point"

`requested_objective_completed` is valid **only if**:
- the in-scope implementation is done,
- the strongest required in-scope verification has been run,
- the current blocker is empty or explicitly external,
- no directly in-scope highest-value next action remains.

If no valid stop reason applies, continue executing within the current task boundary.

---

## 6) Execution Protocol

### 6.1 Default Operating Loop
For any non-trivial change:

1. Identify the exact migration unit
2. Identify the current source of truth in Make
3. Identify the smallest Bazel boundary that can be added safely
4. Implement the narrowest additive change
5. Run the most direct meaningful verification
6. If verification fails, fix and re-verify
7. Record execution state
8. Continue unless a valid stop reason exists

### 6.2 After Every Completed Subgoal
Record all of the following:

- `current_dominant_blocker`: the single biggest thing preventing progress
- `highest_value_next_action`: the most impactful action available right now
- `what_can_break`: untested assumptions and likely failure modes
- `what_can_run_in_parallel`: safe, independent work for subagents
- `verification_evidence`: exact commands and observed outcomes

If `highest_value_next_action` is non-empty and no valid stop reason exists,
take that action immediately.

### 6.3 Verification After Every Change
After every code change:

1. Rerun the most direct end-to-end check for the changed scope
2. Do not commit until that check passes
3. `--nobuild`, static analysis, or lint-only results do **not** count as sufficient verification by themselves
4. Verification must include runtime evidence:
   - actual build output,
   - actual test result,
   - actual generated artifact,
   - actual file content or diff,
   - actual parity evidence
5. If verification fails, fix and re-verify before moving on

Verification should scale with risk:
- package-local change → package-local build/test first
- packaging change → package build + parity + reproducibility evidence if applicable
- image-affecting change → affected image/integration test
- repo-level claim → relevant acceptance gate

---

## 7) Subagent Management

### 7.1 Delegation
Use subagents for bounded, parallelizable subtasks.

Each subagent must receive:
- concrete scope,
- explicit ownership,
- clear output expectations,
- disjoint write scope whenever possible.

The main agent owns:
- plan,
- sequencing,
- delegation,
- integration,
- verification,
- final acceptance.

Subagents assist with execution; they do not decide that work is finished.

### 7.2 Reviewing Subagent Output
Never accept a subagent result based on summary alone.

Required review:
- read actual diffs,
- inspect changed files,
- rerun or extend verification,
- require evidence,
- reject hacked, mocked, or weakly supported work.

Good subagent candidates:
- Make graph tracing for one package
- Dependency extraction for one submodule
- BUILD file authoring for a disjoint directory
- Packaging parity analysis
- Acceptance log triage

---

## 8) Migration Strategy

### 8.1 Unit of Migration
Migrate one bounded unit at a time:
- one package,
- one submodule,
- one service boundary,
- one packaging boundary,
- or one image boundary.

Do not blend unrelated migration units in a single step unless required by a direct dependency edge.

### 8.2 Dependency Order
Preferred order:
- leaves first
- then shared libraries (especially `libswsscommon`)
- then services
- then images
- then broad platform/image aggregation

### 8.3 Builder Classification
Before writing Bazel, classify the current build shape:

- autotools / configure / make
- cmake
- plain make
- python / stdeb
- debian packaging wrapper
- docker/image assembly
- copy/download/prebuilt artifact
- kernel / onie / platform-specific flow

Do not write Bazel first and reverse-engineer intent later.

### 8.4 Build Modeling Rules
Always distinguish these layers explicitly:

- source/build targets
- generated files
- packaging targets
- runtime/image composition
- fetched/prebuilt artifacts
- platform-specific overlays

Do **not** assume one `.deb` maps cleanly to one Bazel target.

When modeling dependencies, distinguish:
- build-time deps
- runtime deps
- image composition deps
- tool/bootstrap deps

### 8.5 Upstreamable Coexistence Rules
- Keep original Make rules in place
- Preserve existing Make target names, recipe variables, and ownership documentation unless a separate objective says otherwise
- New Bazel targets should coexist with Make, not silently replace it
- If a Make rule becomes misleading after Bazel migration, update documentation or comments before considering structural changes
- Never propose a Make-removal wave as the default next step

### 8.6 Submodule Rules
- Use `rules_foreign_cc` (for example `configure_make()`) for submodules with existing autotools-style build systems
- Use native `cc_library` only when the submodule has no meaningful existing build system
- If a submodule already uses Bazel internally, depend on its Bazel targets directly when practical
- Never perform submodule mutation inside build actions

---

## 9) Bazel Conventions

- `bzlmod` only: use `MODULE.bazel`, never `WORKSPACE`
- All BUILD / `.bzl` files must be formatted with `buildifier` before commit
- Target names: `lower_snake_case`
- Base image digests pinned by `sha256`
- Never use `glob()` when files can be listed explicitly
- Put `select()` expressions at the bottom of the target where practical
- Prefer explicit, local BUILD targets over premature repo-wide macro abstraction
- Do not introduce opaque shell-based build steps when a proper Bazel rule is feasible

---

## 10) Package-Level Verification Requirements

Before moving from one package to the next, the current package should satisfy
all relevant checks below unless explicitly marked blocked:

- [ ] `bazel build` succeeds with `--sandbox_default_allow_network=false`
- [ ] package `bazel test` target passes if applicable
- [ ] parity evidence exists against the Make output or behavior
- [ ] if packaging changed: `debdiff make.deb bazel.deb` is timestamps-only or otherwise explained
- [ ] if reproducibility is expected: two clean builds produce identical `sha256`
- [ ] no `no-sandbox` tag introduced anywhere in the changed scope
- [ ] original Make rules remain present
- [ ] what remains Make-owned is stated explicitly

If a box is unchecked, explain why.

---

## 11) Evidence Requirements for Claims

Never claim success without naming the evidence.

For any meaningful claim, state:
- what changed,
- which files changed,
- what command(s) were run,
- what passed,
- what failed,
- what remains unverified,
- what still belongs to Make,
- whether original Make rules were preserved,
- what the next highest-value action is.

---

## 12) Commit Format

```text
<type>(<scope>): <subject>
```

Allowed `type`:
- `feat`
- `fix`
- `refactor`
- `build`
- `ci`
- `docs`
- `test`
- `chore`

Preferred `scope`:
- `bazel`
- `deb`
- `oci`
- `onie`
- `platform/<name>`
- `rules`
- `ci`
