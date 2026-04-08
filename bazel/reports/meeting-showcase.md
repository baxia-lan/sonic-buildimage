# SONiC Bazel Migration Showcase

Last updated: 2026-04-07
Branch: `codex/codex`
Commit: `3bcd3c85e`

## What We Can Show Now

This demo should focus on things that have already been verified locally:

- Bazel is building a real SONiC runtime artifact, not just placeholder graph metadata.
- `docker-sonic-vs.gz` builds successfully from the parent `sonic-buildimage` repo.
- Bazel exports the artifact into the legacy-compatible `target/` layout.
- The artifact is valid as a gzip archive and can be loaded by Docker.
- We now have a CI-grade non-hermeticity audit that makes the remaining migration debt explicit.

Do not present Broadcom kernel / ONIE as complete. That line is in progress.

## Current Verified Artifact

Artifact:

- `bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz`
- `bazel-bin/images/oci/docker-sonic-vs/target_tree/target/docker-sonic-vs.gz`

Verified facts:

- Bazel target:
  - `//images/oci/docker-sonic-vs:image`
  - `//images/oci/docker-sonic-vs:target_tree`
- Size: `657M`
- SHA256: `71b645db43afa6deed6d8ddcad8e6ac0993a5a02486fa0e83a2368eaa66ff745`
- `gzip -t` passes
- `docker load -i bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz` succeeds

## Recommended 5-Minute Demo

### 1. Show the branch and current milestone

Say:

> We have already moved one real service artifact onto a Bazel-owned path in the main repo. This is not a fake BUILD graph; Bazel produces a real `docker-sonic-vs.gz`.

Run:

```bash
git rev-parse --short HEAD
git log --oneline -n 5
```

### 2. Show the Bazel target and artifact path

Say:

> The canonical Bazel interface is `//images/oci/docker-sonic-vs:image`, and Bazel also exports the compatibility artifact under `target/docker-sonic-vs.gz`.

Run:

```bash
./tools/bazel/bazelw --batch build --config=ci \
  //images/oci/docker-sonic-vs:image \
  //images/oci/docker-sonic-vs:target_tree
```

Then:

```bash
ls -lh \
  bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz \
  bazel-bin/images/oci/docker-sonic-vs/target_tree/target/docker-sonic-vs.gz
```

### 3. Show that the output is real and loadable

Say:

> We validated the output as a real runtime artifact: the gzip is valid and Docker can load it.

Run:

```bash
gzip -t bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz
shasum -a 256 bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz
docker load -i bazel-bin/images/oci/docker-sonic-vs/docker-sonic-vs.gz
```

Expected talking point:

> This demonstrates that Bazel is already producing a real SONiC image artifact in the parent repo, not only intermediate metadata.

### 4. Show that the remaining debt is now measurable

Say:

> We also turned the remaining non-hermetic migration debt into an auditable CI artifact, so the cleanup work is now measurable instead of informal.

Run:

```bash
python3 tools/ci/collect_nonhermetic_deps.py --format markdown | sed -n '1,40p'
```

Current summary:

- total issues: `355`
- `HIGH`: `41`
- `MEDIUM`: `314`

Expected talking point:

> The migration is now split into two tracks: keep shipping real Bazel-built artifacts, and systematically burn down non-hermetic execution-time fetches.

## Recommended Storyline

Use this sequence:

1. **Problem**
   - Make is the historical source of truth, but it is too fragmented and expensive to maintain.
   - Current build paths still hide network fetches and mutable external state.

2. **What changed**
   - Bazel is now producing a real artifact from the main repo: `docker-sonic-vs.gz`.
   - We hardened the legacy bridge enough to get through real Docker image production.
   - We added automated non-hermeticity auditing to make the remaining migration debt explicit.

3. **Why this matters**
   - We have crossed from planning/scaffolding into real artifact ownership.
   - We can now demonstrate value with an actual output while continuing to replace the legacy bridge.

4. **What is still not done**
   - Broadcom ONIE / `sonic-broadcom.bin` is not complete yet.
   - The real Linux kernel is not yet built and verified by the current branch.
   - The bridge still needs review fixes:
     - correct Bazel input declaration
     - no execution-time `apt` / `pip`
     - concrete `.deb` rule output conflict fix

## What Not To Claim

Do not claim any of the following in the meeting:

- that Broadcom ONIE is complete
- that the Linux kernel build is complete
- that the build is already fully hermetic
- that Make has already been eliminated

## Suggested Slide Title

`SONiC Make -> Bazel Migration: First Real Artifact, Measurable Hermeticity Debt`

## Suggested Close

> We now have a credible transition point: Bazel is producing a real SONiC runtime artifact in the main repo, and the remaining migration work is visible as explicit technical debt rather than hidden build behavior.
