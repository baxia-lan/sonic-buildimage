# Migration Process — Make to Bazel

**Date**: 2026-04-22
**Branch**: `claude` on [`baxia-lan/sonic-buildimage`](https://github.com/baxia-lan/sonic-buildimage)
**Commits on branch**: 267 ahead of `master` (upstream base: 202405)

This document is a sharable snapshot of where the migration is and how it is being
done. Engineering detail (gate-level blockers, root causes, file-by-file state)
lives in [`handoff.md`](./handoff.md). Execution protocol lives in [`../CLAUDE.md`](../CLAUDE.md).

---

## What this fork is doing

Migrating SONiC buildimage from GNU Make to Bazel (`bzlmod`), with hermetic
build actions as a hard requirement. Make rules stay in place and functional;
Bazel is added beside them. The end state is intended to be upstreamable, so the
default posture is **coexistence**, not replacement.

Reference implementation used for patterns:
[thesayyn/sonic-buildimage](https://github.com/thesayyn/sonic-buildimage).

---

## Four acceptance gates

| Gate | Output | Current status |
|------|--------|----------------|
| 1 | `docker-sonic-vs.gz` | VS image boots under Bazel. CI runs **12 tests passing** (of 18 collected across `test_port.py` / `test_admin_status.py` / `test_speed.py` — 6 deselected with documented vs-SAI / env reasons). sonic-swss ships 710 tests total; widening is pending. FRR `dplane_fpm_sonic.so` is still the open blocker for full parity. |
| 2 | Cloud Build CI | Green path on the primary CI (Cloud Build, 32 vCPU). Remote cache shared across steps. Step-level retry added for transient GitHub 504s. Commit-status posting still needs end-to-end verification. |
| 3 | `sonic-broadcom.bin` | Hermetic broadcom build landed (kernel + SAI + service images, no stubs). Full acceptance test against a real `.bin` has not been run. |
| 4 | `sonic-alpinevs.img.gz` | Alpine VS Docker image pinned, caching enabled. Acceptance test not yet attempted. |

Acceptance criteria for each gate are defined in [`../CLAUDE.md`](../CLAUDE.md).

---

## Approach

- **Coexistence, not replacement.** Make rules remain the source of truth during
  migration. Bazel is added alongside; when Make and Bazel disagree, Make wins
  until parity is proven.
- **Leaves first.** Dependency order:
  `libnl3 / libpcre3 / libyang` → `swss-common` → `sairedis` → `swss` →
  docker layers → image.
- **White-box analysis.** Every dependency added is traced from binary →
  `ldd` → shared library → Debian package. No speculative `apt` additions.
- **Hermeticity is enforced, not aspirational.** `--sandbox_default_allow_network=false`
  is the default. All downloads pinned by `sha256`. `SOURCE_DATE_EPOCH=0` on
  packaging actions. No `apt-get`, `git submodule update`, or `dpkg-buildpackage`
  network access inside build actions.
- **One migration unit at a time.** One package, one submodule, one packaging
  boundary, or one image — never blended.

---

## How the CI runs

- **Primary: Cloud Build** (32 vCPU, 28.8 GB RAM, 200 GB disk) on push to
  `claude`. Remote cache: `gs://sonic-bazel-cache`. Config: `cloudbuild.yaml`.
- **Secondary: GitHub Actions** (2 vCPU, lightweight) — boot test only,
  no `pytest`. Config: `.github/workflows/build-orchagent.yml`.

Build graph on Cloud Build:

```
init-submodules -> align-submodules -> copy-build-files -+
install-bazelisk ----------------------------------------+
   |
   +-> build-orchagent -+-> build-docker-sonic-vs -> verify-vs -> pytest-vs
   |                    +-> build-service-images
   |                    +-> swss-common-unit-tests / sairedis-unit-tests / swss-mock-tests
   |                    +-> build-broadcom-bin
   +-> build-kernel (serialized after build-orchagent to avoid lock contention)
   +-> summary -> github-status
```

---

## Recent progress (since 2026-04-15)

- **FRR layer hermeticity**: `usrmerge` fix applied in `frr_deb_repo` and
  `vs_frr_layer`; missing runtime libs added (`libjson-c5`, `libc-ares2`,
  `libbpf1`, `jq`, `libjq1`, `libonig5`).
- **FRR deps fetch**: Docker-based genrule replaced with a `repository_rule`
  so fetches happen at `bazel fetch` time, not at action time.
- **Broadcom**: Fully hermetic broadcom build landed — all service images, no
  stubs.
- **Alpine VS**: Docker image pinned by digest, caching enabled.
- **Cloud Build resilience**: `repository_cache` shared across CB steps;
  step-level retry for transient 504s on `repository_rule` HTTP fetches.
- **CI pytest-vs**: 3 sonic-swss test files (`test_port.py`,
  `test_admin_status.py`, `test_speed.py`), 18 tests collected, 6 deselected
  with documented reasons, **12 passing**. `test_vlan.py` is *not* in the
  current invocation (VLAN-create → ASIC_DB plumbing issue tracked separately).

---

## pytest-vs — what is actually being verified

| | Count |
|---|---|
| sonic-swss total test files | 95 |
| sonic-swss total test functions | 710 |
| Files in CI (`test_port` / `test_admin_status` / `test_speed`) | 3 |
| Tests collected | 18 |
| Deselected (vs-SAI gaps / env artifacts — see [`handoff.md`](./handoff.md)) | 6 |
| **Passing on Cloud Build** | **12** |
| Current coverage | ~1.7% of sonic-swss |

Each deselection is inline-documented in `cloudbuild.yaml`. Files not yet
attempted in this CI lane: ACL, route, CRM, interface, neighbor, nhg, fdb,
vlan, buffer, and many more. Widening to the full sonic-swss suite is what
Gate 1 acceptance actually requires.

## What is still open

1. **Widen `pytest-vs` toward the full sonic-swss suite.** Gate 1 acceptance
   requires the full suite, not a 12-test subset.
2. **FRR `dplane_fpm_sonic.so`.** Upstream `@frr` 10.6.0 (pulled from
   `deb.frrouting.org` in `MODULE.bazel`) lacks the SONiC-specific zebra
   module. `src/sonic-frr/BUILD.bazel` has the source-build wiring but is
   not yet consumed by the VS image.
3. **Cloud Build commit-status posting** — end-to-end verification.
4. **Gate 3 acceptance test** — run against a real `sonic-broadcom.bin`.
5. **Gate 4** — `sonic-alpinevs.img.gz` acceptance not yet started.

---

## How to build and boot the VS image locally

Hermetic Bazel path (the migration target):

```bash
bazel build //platform/vs:docker_sonic_vs_tarball \
  --sandbox_default_allow_network=false --jobs=4

bash bazel-bin/platform/vs/docker_sonic_vs_tarball.sh
docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest
docker run --privileged docker-sonic-vs:latest
```

Make path (still ground truth during migration):

```bash
make target/docker-sonic-vs.gz
```

---

## Where to go next

- Deep engineering state, blocker detail, ELF analysis, file-level ownership:
  [`handoff.md`](./handoff.md)
- Bazel-migration focused README (architecture, how-to-build):
  [`README_BAZEL.md`](./README_BAZEL.md)
- Hard rules this repo follows for the migration:
  [`../CLAUDE.md`](../CLAUDE.md)
- Upstream SONiC build instructions (Make system):
  [`../README.md`](../README.md)
