# AGENTS.md

## Scope

This file defines the repository-wide rules for `sonic-buildimage`.

Keep this file short, stable, and normative. Only put rules here that should
apply to nearly every future task. Detailed migration sequencing, wave
planning, and implementation tactics belong in [AGENT.md](AGENT.md).

## Rule 1: Bazel Owns the Build

- Bazel 8.5.0 + Bzlmod is the long-term build system.
- Bazel is the source of truth for every publishable artifact.
- Legacy Make metadata may be used as migration input, but not as a permanent
  parallel source of truth.
- Do not add new long-term public Make targets for migrated artifacts.

## Rule 2: All Publishable Artifacts Move Under Bazel

The Bazel graph must own:

- Debian packages (`.deb`)
- Python wheels (`.whl`)
- Go binaries
- OCI images
- host images
- installer images, including outputs such as `sonic-broadcom.bin`

Prefer the standardized public APIs in `bazel/sonic/`:

- `sonic_deb_package`
- `sonic_py_wheel`
- `sonic_go_binary`
- `sonic_oci_image`
- `sonic_host_image`
- `sonic_platform`

If one of these shapes fits, do not invent a new public rule shape.

## Rule 3: Public Interfaces Must Stay Predictable

Public Bazel labels must keep these shapes:

- `//packages/deb/<name>:deb`
- `//packages/wheel/<name>:wheel`
- `//packages/go/<name>:bin`
- `//images/oci/<name>:image`
- `//images/host/<name>:image`
- `//platforms/<name>:platform`
- `//installers/<platform>:onie`
- `//installers/<platform>:raw`
- `//installers/<platform>:aboot`
- `//installers/<platform>:kvm`

The Bazel label is the canonical interface. `target/` is a compatibility export
surface only, and it must be produced by Bazel rather than Make.

## Rule 4: Manifests Replace Scattered Make Metadata

- Replace `rules/*.mk` and `platform/*/*.mk` metadata with structured Bazel
  manifests.
- Put artifact ownership, build dependencies, runtime dependencies, files,
  service or image composition, platform payloads, installer contents, and
  release or export metadata in Bazel-owned manifests before expanding rule
  implementations.
- Prefer Starlark-native manifests and repo macros over new shell glue or
  template-only orchestration.
- A migration PR must move graph ownership, not just copy files.

## Rule 5: Distro Scope Must Shrink, Not Grow

First-class Bazel distro targets are:

- `bookworm`
- `trixie`

These may remain as temporary migration inputs, but must not become new primary
Bazel targets:

- `bullseye`
- `buster`
- `stretch`

## Rule 6: Dependencies Must Be Explicit, Pinned, and Reducible

- Declare external dependencies through `MODULE.bazel` and `MODULE.bazel.lock`.
- Do not add new long-term dependency logic to `WORKSPACE`.
- Put non-BCR dependency logic in `bazel/repositories/`.
- Pin every fetched input by digest, checksum, or immutable version.
- Any `MODULE.bazel` change must be followed by regenerating
  `MODULE.bazel.lock`, preferably with `./tools/bazel/bazelw mod deps`.
- Every runtime dependency must have an owner, a purpose, and a removal path or
  permanence justification.

## Rule 7: Bazel Execution Must Stay Hermetic

- Bazel actions must not fetch from the public network during execution.
- Do not use ad hoc `apt-get`, `pip install`, `curl`, or `wget` in Bazel-era
  image assembly, service Dockerfiles, or installer assembly.
- Networked fetching is limited to pinned repository and module resolution
  paths.
- CI must enforce a no-egress check for Bazel execution phases.

## Rule 8: Submodules Are Overlay-First

- Keep vendor and upstream submodules clean by default.
- Prefer overlays, repository macros, module extensions, or patches under
  `bazel/repositories/` before editing submodules directly.
- Only place BUILD or `.bzl` files inside a submodule when that metadata is
  intended to live upstream.
- Do not create vendor-local Bazel forks without a clear owner and upstream
  strategy.

## Rule 9: Intermediate Image Layers Are Internal, Not Products

- Intermediate images such as `docker-config-engine` and `docker-swss-layer`
  are migration inputs, not long-term public release artifacts.
- The target image shape is:
  `base distro rootfs -> shared runtime fragment -> final service image`
- Final service images must contain runtime dependencies only.
- Build-only tools, compilers, and transitive build junk must not leak into
  release images.
- Runtime dependency count, image size, layer count, and duplicate filesystem
  content are tracked regression metrics and must trend down or stay flat with a
  documented exception.

## Rule 10: CI and Reviews Must Prove the Change

Primary CI runs on GCP. The long-term topology is:

- Cloud Build private pools in `us-central1` and `us-east1`
- Artifact Registry in the `us` multi-region
- self-hosted Bazel remote cache and remote execution on GKE

Azure Pipelines may remain as a secondary platform during migration, but it
must consume Bazel-built artifacts instead of invoking the old Make graph.

New Bazel outputs are accepted based on:

- functional parity
- SBOM parity
- dependency-boundary parity

They do not need to be bit-for-bit identical to Make-era outputs.

At minimum, CI and local validation must cover:

- affected-target build
- affected-target test where tests exist
- hermeticity or no-egress checks
- dependency deltas
- size or layer regressions when runtime artifacts change
- installability, loadability, bootability, or service startup as applicable
- required runtime files

If a migrated target does not yet have a meaningful automated test, the change
must include documented smoke, runtime, install, or boot validation instead of
silently skipping verification.

Every migration PR must state:

- why the change exists
- what moved from Make to Bazel
- how it was verified
- dependency delta
- size or layer delta
- rollback impact

If those items are missing, the change is incomplete.
