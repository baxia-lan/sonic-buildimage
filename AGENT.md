# AGENT.md

## Role

This file is the execution playbook for the SONiC buildimage Bazel migration.
`AGENTS.md` defines the non-negotiable rules. This file turns those rules into
an implementation plan, delivery sequence, and validation ladder.
The repo-local Codex operating layer for this playbook lives under:

- `.codex/` for project-scoped Codex config and named agent roles
- `.agents/skills/` for repeatable migration workflows
- `ops/tasks/` for task packs, templates, and the current execution plan

Use [ops/tasks/PLAN.md](ops/tasks/PLAN.md) as the current task-pack view of the
phase plan below.

## Problem Statement

The current build graph is difficult to maintain because the same logical
artifact is spread across Make variables, distro branches, shell glue, Docker
templating, and submodule-local build systems.

The repository evidence is already visible in-tree:

- `Makefile` fans the graph out by distro through `Makefile.work`.
- `slave.mk` binds large parts of the build to mutable `sonic-slave-$(BLDENV)`
  state.
- `rules/docker-*.mk` model image inheritance in Make metadata instead of a
  typed artifact graph.
- `dockers/docker-orchagent/Dockerfile.j2` still uses `apt-get` and `pip3
  install`, which is the opposite of hermetic image assembly.
- `.gitmodules` currently declares 49 submodules, so any migration plan that
  edits vendor trees directly will create long-term maintenance debt.

The result is predictable:

- duplicated dependency logic across distros
- non-hermetic image construction
- too many intermediate image layers
- oversized final artifacts such as `sonic-broadcom.bin`
- slow reviews because graph changes are hidden in Make indirection

## Program Goals

The migration is complete only when all of the following are true:

- Bazel + Bzlmod is the only source of truth for publishable artifacts.
- All `.deb`, `.whl`, Go binaries, OCI images, host images, and installer
  images are built by Bazel rules.
- Runtime images are assembled from pinned filesystem fragments, not from ad
  hoc package installs inside Dockerfiles.
- `docker-config-engine` and `docker-swss-layer` stop being public release
  artifacts and become internal composition units.
- Runtime dependency count, image layer count, duplicate filesystem content,
  and final size are all ratcheted downward or held flat with an explicit
  exception.
- CI runs on GCP with regional failover, hermeticity checks, affected-target
  gates, and reproducibility checks.

## Architecture Decisions

### 1. `sonic-slave-*` is build infrastructure, not a release artifact

`sonic-slave-bullseye` is currently acting as a mutable build environment.
During migration it should be decomposed into:

- Bazel toolchains and execution platforms for build-time behavior
- pinned distro/rootfs inputs for runtime behavior

Do not recreate `sonic-slave-*` as another permanent public Bazel image. That
would rename the old impurity instead of removing it.

### 2. Shared container state becomes internal runtime fragments

The current chain:

`sonic-slave-bullseye -> docker-base -> docker-config-engine -> docker-swss-layer -> docker-orchagent`

must be replaced with:

`pinned distro rootfs -> shared SONiC runtime fragment -> service-specific fragment -> final OCI image`

Under the new model:

- `docker-base-*` becomes a pinned base rootfs plus explicitly selected runtime
  packages.
- `docker-config-engine-*` becomes an internal config/runtime fragment.
- `docker-swss-layer-*` becomes an internal SWSS runtime fragment.
- `docker-orchagent` becomes a final image assembled from those fragments.

Only the final image remains public.

### 3. Manifests come first, macros come second

The existing public Bazel API surface in `bazel/sonic/defs.bzl` is still
scaffold-only. Before artifact macros are made real, every migrated artifact
must have a structured manifest that declares:

- build dependencies
- runtime dependencies
- files and templates
- Python wheels
- image composition inputs
- export metadata
- platform and installer payload membership

Use Starlark manifests that live next to the owning artifact. Avoid YAML/JSON
parsers unless there is a demonstrated need.

### 4. Submodule integration is overlay-first

The default policy for the 49 submodules is:

- no direct edits unless there is an owner and an upstream strategy
- prefer overlays, repository rules, module extensions, and patch application
  in `bazel/repositories/`
- keep Bazel metadata in the parent repo unless the submodule is the correct
  long-term home for that metadata

### 5. Bullseye can be a migration baseline, not a new primary track

The first decomposition wave may analyze the current bullseye chain because it
is a real dependency path today. That does not make bullseye a Bazel-era
first-class distro. Mainline Bazel targets remain centered on `bookworm` and
`trixie`, with bullseye kept only as a temporary compatibility input.

## Required Repo Shape

The repo should converge on this working layout:

- `bazel/repositories/`: module extensions, pinned fetch helpers, submodule
  overlays, patch logic
- `bazel/sonic/`: repo-wide macros, shared providers, transitions, export rules
- `packages/deb/<name>/`: manifest + `:deb`
- `packages/wheel/<name>/`: manifest + `:wheel`
- `packages/go/<name>/`: manifest + `:bin`
- `images/oci/<name>/`: manifest + `:image`
- `installers/<platform>/`: manifest + `:onie`, `:raw`, `:aboot`, `:kvm`

Compatibility exports to `target/` are allowed only as explicit Bazel outputs.

## Delivery Model

Each migration change must move one closed slice of the graph and remove
ambiguity. A valid migration PR does all of the following in one reviewable
unit:

- converts metadata into a Bazel-owned manifest
- introduces or completes the required Bazel macro behavior
- wires the artifact into the public label shape
- adds verification for the changed graph
- records dependency, layer, and size impact
- documents rollback impact

A PR that only shuffles files without changing graph ownership is incomplete.

## Phase Plan

### Phase 0: Baseline Capture

Capture the current graph before large refactors.

Required outputs:

- inventory of Debian packages, wheels, Go binaries, OCI images, host images,
  and installers
- dependency snapshots for representative images and `sonic-broadcom.bin`
- layer count and size baselines
- submodule ownership map

Exit criteria:

- baseline artifacts and metrics are committed or reproducibly generated
- first-wave target list is frozen

### Phase 1: Bazel Foundation

Complete the common migration substrate.

Required work:

- keep `MODULE.bazel`, `MODULE.bazel.lock`, `.bazelrc`, `.bazelversion`, and
  `tools/bazel/bazelw` authoritative
- move all non-BCR fetching under `bazel/repositories/`
- implement compatibility export rules for `target/`
- harden CI entrypoints in `tools/ci/`

Exit criteria:

- lockfile-enforced CI passes
- no new dependency logic lands in `WORKSPACE`
- no-egress checks are part of presubmit

### Phase 2: Artifact API Activation

Turn scaffold macros into real artifact rules.

Required work:

- implement `sonic_deb_package`
- implement `sonic_py_wheel`
- implement `sonic_go_binary`
- implement `sonic_oci_image`
- implement `sonic_host_image`
- implement `sonic_platform`

Exit criteria:

- representative `.deb`, `.whl`, and Go targets build under Bazel
- public labels follow the repo-wide naming contract

### Phase 3: First Image Refactor Wave

Target the current chain:

`sonic-slave-bullseye -> docker-base-bullseye -> docker-config-engine-bullseye -> docker-swss-layer-bullseye -> docker-orchagent`

Required work:

1. Freeze the exact runtime dependency set used by that chain today.
2. Split build-only state out of `sonic-slave-bullseye` into toolchains and
   execution-platform configuration.
3. Model `docker-base-bullseye` as a pinned rootfs plus an explicit runtime
   package manifest.
4. Convert `docker-config-engine-bullseye` into an internal config/runtime
   fragment with no public release identity.
5. Convert `docker-swss-layer-bullseye` into an internal SWSS fragment with no
   public release identity.
6. Build `docker-orchagent` as the first fully Bazel-assembled final service
   image.
7. Preserve any required `target/` compatibility export via Bazel, not Make.

Why this wave comes first:

- it attacks the current most obvious layer explosion
- it forces the package, wheel, image, and export APIs to work together
- it creates a reusable pattern for `fpm`, `sflow`, `iccpd`, `macsec`, `nat`,
  and other images currently based on `docker-swss-layer-*`

Exit criteria:

- `docker-orchagent` builds from Bazel only
- required runtime files are present
- service startup smoke passes in the selected validation environment
- layer count is reduced or unchanged
- final image size is reduced or unchanged unless a written exception is
  approved

### Phase 4: Package and Image Expansion

Scale the same pattern across the remaining service image graph.

Required work:

- migrate all config-engine consumers to internal runtime fragments
- migrate all swss-layer consumers to internal SWSS fragments
- eliminate service Dockerfiles that still perform package installation during
  image assembly

Exit criteria:

- no Bazel-managed service image uses ad hoc `apt-get`, `pip install`, `curl`,
  or `wget`
- shared runtime fragments replace public intermediate images

### Phase 5: Host and Installer Images

Move platform and installer production under Bazel.

Required work:

- define structured manifests for platform payloads
- define installer composition for ONIE, raw, aboot, and KVM
- move host image assembly for outputs such as `sonic-broadcom.bin` to Bazel

Exit criteria:

- representative Broadcom, Mellanox/NVIDIA, Marvell, VS, and ARM outputs build
  via Bazel labels
- bootability and installability checks pass

### Phase 6: Make Retirement

Remove the old graph once parity is demonstrated.

Required work:

- delete or freeze legacy Make entrypoints for migrated artifacts
- ensure CI, release automation, and secondary Azure jobs consume Bazel outputs
- document remaining compatibility shims and their deletion path

Exit criteria:

- mainline artifact production does not invoke Make
- Make survives only as a bounded migration aid, or is removed entirely

## CI and Availability Plan

GCP is the primary CI and release environment.

Required topology:

- Cloud Build private pool in `us-central1` as primary
- Cloud Build private pool in `us-east1` as hot standby
- Artifact Registry in `us` multi-region
- self-hosted Bazel remote cache and remote execution on regional GKE clusters
- failover plan that keeps presubmit and nightly builds running when one region
  is degraded

Required pipelines:

- presubmit: affected-target build/test, lockfile enforcement, no-egress check,
  dependency delta, size/layer checks for touched images
- nightly: representative package, service image, installer, VS/KVM, vendor,
  and ARM coverage
- reproducibility: same commit built twice with equivalent outputs

Existing repo entrypoints that should remain the CI contract:

- `tools/ci/run_affected_targets.sh`
- `tools/ci/run_nightly_matrix.sh`
- `tools/ci/run_repro_check.sh`
- `tools/ci/verify_no_egress.sh`

## Dependency and Size Reduction Rules

Every migration wave must remove complexity, not just rename it.

Required behavior:

- separate build-only dependencies from runtime dependencies
- deduplicate files shared across service images
- make package ownership visible in manifests
- require an owner, purpose, and removal path for every runtime dependency
- reject new dependencies that do not materially improve function or reliability

Required metrics for every runtime-affecting PR:

- dependency delta
- layer-count delta
- image-size delta
- duplicate-file delta, when image contents changed
- rollback impact

`sonic-broadcom.bin` is currently close to 1 GiB. The program must treat that as
a regression signal, not as an acceptable steady state.

## Validation Ladder

Every migration slice must be self-validated before review.

Minimum validation:

1. `bazel build --config=ci` on affected targets
2. `bazel test --config=ci` where tests exist
3. no-egress verification
4. dependency manifest diff
5. layer-count and size comparison for touched images
6. required runtime file presence check

Required final validation for `docker-sonic-vs.gz` and any migration slice that
claims VS runtime parity:

1. Bazel must build `//images/oci/docker-sonic-vs:image` hermetically under
   `--config=ci`.
2. The produced `docker-sonic-vs.gz` must be loaded and used as the image under
   test for `src/sonic-swss/tests`.
3. `sonic-swss` pytest coverage must pass against that Bazel-built image before
   the artifact can be described as functionally correct.
4. `gzip -t`, digest capture, and `docker load` are required smoke checks, but
   they do not replace the `sonic-swss` pytest gate.

Additional validation when applicable:

- service startup smoke test
- installer loadability or bootability check
- SBOM parity check
- reproducibility rerun
- platform-specific hardware or VS coverage

Functional parity, SBOM parity, and dependency-boundary parity matter more than
bit-for-bit identity.

## Review Checklist

Every migration PR description must answer these questions:

- Why does this change exist?
- What part of the graph moved from Make to Bazel?
- What dependencies moved, appeared, or disappeared?
- What was the size and layer impact?
- How was the result verified?
- What is the rollback path?

If those answers are missing, the change is not ready for merge.
