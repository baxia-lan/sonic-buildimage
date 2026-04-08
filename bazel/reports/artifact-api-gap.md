# SONiC Bazel Artifact API Gap Report

## Scope

This report describes what still separates the current public SONiC Bazel
artifact APIs from real publishable builders in this repo.

Today the public names in `bazel/sonic/defs.bzl` all forward directly to
`bazel/sonic/private/artifacts.bzl`, and that file only emits manifest and lock
JSON. The default migration stage is `manifest_only`, so the current APIs are
manifest wrappers, not concrete artifact builders.

That is useful for graph capture, but it does not yet satisfy the repo rules in
`AGENTS.md`: Bazel is not yet producing the final `.deb`, `.whl`, Go, OCI,
host-image, or installer bytes for most of these public labels.

## Current Repo State

- `sonic_deb_package`, `sonic_py_wheel`, `sonic_go_binary`, `sonic_oci_image`,
  `sonic_host_image`, and `sonic_platform` all share the same
  `_artifact_manifest` implementation.
- `_artifact_manifest` records dependency metadata, composition metadata,
  source ownership, and a transitive graph summary, but it does not emit a real
  `.deb`, `.whl`, executable, OCI archive, host image, or installer image.
- `sonic_export_to_target_tree` already exists and is usable for compatibility
  exports once a label produces concrete bytes.
- `legacy_artifact_bridge` now provides a temporary local concrete path for a
  few targets such as `//images/oci/docker-sonic-vs:image`, but that bridge is
  explicitly transitional and should not become the long-term public API
  behavior.
- Bridge-backed targets are evidence-gathering aids only. They do not count as
  migrated outputs under the repo policy because Bazel still is not generating
  the final bytes itself.

## Cross-Cutting Gaps

The same core gaps appear across every public API:

1. The rule output shape is wrong. The public labels mostly return manifest and
   lock files instead of the publishable artifact the label name implies.
2. The rule providers are too weak. Downstream rules can read metadata, but
   they cannot consume concrete package, wheel, binary, filesystem, or image
   outputs in a typed way.
3. The proof contract is incomplete. The repo has CI helpers such as
   `tools/ci/run_affected_targets.sh`, `tools/ci/run_image_metrics_check.sh`,
   and `tools/ci/verify_no_egress.sh`, but the artifact APIs do not yet define
   the validation expected for each artifact kind.
4. The public API and the concrete builder are disconnected. Where concrete
   bytes exist today, they are produced by a custom review path or a private
   bridge, not by the public artifact macro itself.
5. Hermeticity is not enforced at the artifact boundary. OCI work in
   particular still depends on Dockerfiles with `apt-get` and `pip`, which
   violates the repo direction for Bazel-era image assembly.
6. Review or bridge success is not an exit condition. The migration is only
   complete once the public Bazel label emits the final artifact bytes with no
   Make execution hidden behind it.

## API By API

### `sonic_deb_package`

Current state:

- Used by repo-owned labels such as `//packages/deb/libswsscommon:deb`,
  `//packages/deb/swss:deb`, and `//packages/deb/sonic-db-cli:deb`.
- The manifests already capture legacy package names, source ownership,
  transitive Bazel runtime edges, and wheel dependencies.
- The label still does not emit a `.deb`.

Next concrete step:

- Keep the manifest and lock as side outputs, but make `:deb` produce a real
  package file.
- Start with the closed orchagent slice packages already referenced by the
  image chain: `libswsscommon`, `sonic-db-cli`, `sonic-eventd`, `libsairedis`,
  `libdashapi`, and `swss`.
- Make the rule expose typed outputs needed by `sonic_oci_image` so images can
  assemble runtime package contents without falling back to legacy Dockerfile
  installation.

Required proof:

- `./tools/bazel/bazelw --batch build --config=ci` succeeds for the affected
  `//packages/deb/...` labels.
- Package installability is checked with offline package inspection and at
  least one runtime consumer build.
- Dependency deltas versus the manifest baseline are recorded.
- If a package is later consumed by an OCI target, the image validation must
  prove the package landed as runtime content and not only as a build-time
  dependency.

### `sonic_py_wheel`

Current state:

- Used by labels such as `//packages/wheel/sonic_config_engine:wheel`,
  `//packages/wheel/sonic_yang_mgmt:wheel`, and `//packages/wheel/scapy:wheel`.
- The manifests capture source ownership and wheel-on-wheel relationships.
- The label still does not emit a `.whl`.

Next concrete step:

- Make `:wheel` produce an actual wheel while preserving the manifest and lock
  outputs for migration evidence.
- Keep the first implementation limited to the wheels already used by the
  orchagent chain so the new builder closes an existing slice instead of adding
  unused surface area.
- Ensure the rule can describe runtime-only wheel inputs distinctly from build
  helper wheels, because OCI assembly needs the runtime set only.

Required proof:

- Build the wheel labels under `--config=ci`.
- Validate the wheel metadata and archive contents.
- Install or unpack the wheel in an isolated local check and prove the expected
  imports work for the owning runtime path.
- Record dependency changes for any wheel that replaces a legacy `pip install`
  path.

### `sonic_go_binary`

Current state:

- The public API exists in `bazel/sonic/defs.bzl`.
- There are currently no repo consumers under `packages/go/<name>:bin`.
- `packages/go/` exists, but the concrete label surface has not been activated.

Next concrete step:

- Do not add placeholder targets with no owner.
- Activate `sonic_go_binary` with the first real Go-owned deliverable in the
  repo, and make the public label emit a real executable plus manifest and lock
  side outputs.
- Ensure the rule defines the binary architecture and any runtime packaging
  expectations up front so the first consumer does not create a one-off shape.

Required proof:

- Build the binary for the intended architecture under `--config=ci`.
- Validate the produced executable format and a minimal smoke path such as
  `--help` or equivalent startup.
- Record runtime dependency expectations if the binary is later embedded into an
  image or installer.

### `sonic_oci_image`

Current state:

- Used by the repo image manifests, including
  `//images/oci/docker-base-bookworm:image`,
  `//images/oci/docker-config-engine-bookworm:image`,
  `//images/oci/docker-swss-layer-bookworm:image`, and
  `//images/oci/docker-orchagent:image`.
- The manifests already model base, fragment, runtime package, wheel, file, and
  source relationships.
- Concrete bytes are still produced outside the public API:
  `//images/oci/docker-orchagent:review_archive` uses a review builder script,
  and `//images/oci/docker-sonic-vs:image` uses `legacy_artifact_bridge`.
- The current review path still uses Docker Buildx and non-hermetic `apt-get`
  and `pip`.

Next concrete step:

- Make `sonic_oci_image` produce the canonical concrete image artifact for the
  owning label, with manifest and lock retained as side outputs.
- For the first implementation, close the existing orchagent slice instead of
  broadening scope: base rootfs, internal config-engine fragment, internal swss
  fragment, and final `docker-orchagent`.
- Replace Dockerfile-driven package installation with Bazel-owned runtime
  inputs. The rule should assemble runtime filesystem content, not replay
  mutable package manager steps.
- Keep `sonic_export_to_target_tree` as the compatibility export surface for
  `target/`, but only after the public `:image` label produces the concrete
  archive itself.

Required proof:

- Affected-target build through `tools/ci/run_affected_targets.sh`.
- No-egress validation through `tools/ci/verify_no_egress.sh`.
- Image metrics and regression checks through
  `tools/ci/run_image_metrics_check.sh`.
- Runtime smoke validation of the produced image, including required files,
  expected commands, dependency imports, and architecture metadata.
- Layer count, size, and dependency deltas recorded in the owning report.

### `sonic_host_image`

Current state:

- The public API exists, but there is no `images/host/<name>:image` rollout yet.
- The current repo uses `sonic_host_image` indirectly through
  `installers/defs.bzl` to declare installer manifests such as
  `installers/broadcom:onie_manifest` and `installers/broadcom:aboot_manifest`.
- That means the public host-image API is currently carrying installer manifest
  metadata rather than producing an actual host image.

Next concrete step:

- Separate “host image bytes” from “installer manifest metadata” in the public
  behavior, even if they continue sharing implementation pieces underneath.
- Introduce real `//images/host/<name>:image` owners before expanding installer
  builders further.
- Keep installer manifests as consumers of platform and payload providers, not
  as a permanent alias for the host-image API.

Required proof:

- Build the concrete host image artifact under `--config=ci`.
- Validate installability, loadability, or bootability as applicable.
- Record required runtime files, dependency deltas, and size changes.
- Prove that any remaining `target/` export is Bazel-owned.

### `sonic_platform`

Current state:

- Activated today through `platforms/defs.bzl` as `sonic_platform_manifest`.
- Labels such as `//platforms/broadcom:platform` do exist, but they still emit
  manifest/lock metadata only.
- Installers depend on those labels for metadata handoff, not for a typed
  platform payload API yet.

Next concrete step:

- Keep the platform label as the canonical interface, but extend it beyond JSON
  metadata so installer and host-image rules can consume typed platform payload
  information.
- Use the existing platform labels as the activation surface instead of adding a
  parallel custom rule family.
- Ensure dependent machine, arch, and installer payload membership stay
  Bazel-owned and queryable.

Required proof:

- Build the affected `//platforms/...:platform` labels.
- Prove the downstream installer or host-image consumer sees the correct
  payload, architecture, and machine metadata.
- Record rollback and compatibility impact for any platform manifest shape
  change.

## Recommended Implementation Order

1. Activate `sonic_deb_package` and `sonic_py_wheel` for the orchagent slice so
   Bazel owns the runtime package and wheel inputs the image needs.
2. Activate `sonic_oci_image` for the orchagent chain and retire the review-only
   image path as the canonical builder.
3. Activate `sonic_platform` and `sonic_host_image` together for the real host
   and installer ownership work in Phase 4.
4. Activate `sonic_go_binary` when the first owned Go deliverable is selected,
   not before.

## Exit Condition For Phase 1

Phase 1 is complete when the public APIs stop being manifest-only wrappers and
each activated label shape produces the concrete artifact its name promises,
with verification and proof attached at the same review boundary.
