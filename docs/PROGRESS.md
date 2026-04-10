# Make→Bazel Migration Progress

Last updated: 2026-04-10

## Three Milestones

### 1. docker-sonic-vs + pytest [IN PROGRESS]

**Goal**: `bazel build //platform/vs:docker_sonic_vs_tarball` → load → pytest passes

| Component | Status | Verified |
|---|---|---|
| OCI image assembly (oci_image, 7 layers) | Done | Analysis passes |
| Runtime apt packages (rules_distroless) | Done | Layer builds |
| SONiC .debs (swss-common, sairedis+syncd-vs, swss) | Done | .debs built from source |
| FRR 10.6.0 (@frr repo, sha256 pinned) | Done | Analysis passes |
| Python layer (sonic-cfggen, sonic-py-common) | Done | Analysis passes |
| supervisord.conf + redis.conf + device data | Done | Config layer builds |
| Boot test (services start) | **NOT DONE** | Waiting for CI |
| pytest test_port.py | **NOT DONE** | Waiting for CI |

**Blockers**: CI needs to complete end-to-end build + load + pytest on Linux.

### 2. Cloud Build CI [IN PROGRESS]

**Goal**: Push to claude → Cloud Build runs → results visible

| Component | Status |
|---|---|
| cloudbuild.yaml (12 steps, N1_HIGHCPU_32) | Done |
| GCS remote cache (gs://sonic-bazel-cache) | Configured |
| GitHub commit status reporting | Done (needs _GITHUB_TOKEN) |
| GCS summary upload | Done |
| Bazel state persistence across steps | Done |
| Trigger on claude branch push | Set up by user |

**Blockers**: First Cloud Build run needs to complete. No way to check logs without GCP access.

### 3. sonic-broadcom.bin [IN PROGRESS]

**Goal**: `bazel build //platform/broadcom:sonic_broadcom_bin` with real kernel

| Component | Status | Verified |
|---|---|---|
| Kernel compilation (dpkg-buildpackage) | Done | Passes in GH Actions CI |
| cpupower fix (remove from debian/control) | Done | Verified in CI |
| Staging dir for outputs | Done | Verified in CI |
| vmlinuz extraction | Done (abs path fix) | Waiting for CI |
| kernel_modules_tar extraction | Done (abs path fix) | Waiting for CI |
| ONIE image assembly (sharch format) | Done | Analysis passes |
| onie_image_builder.sh --installer fix | Done | Not verified |
| End-to-end broadcom.bin | **NOT DONE** | Previous CI: disk space error → freed 30GB |

**Blockers**: vmlinuz Docker volume mount fix needs CI verification.

## Infrastructure

- Bazel 8.5.1 + bzlmod, MODULE.bazel.lock committed
- rules_distroless 0.3.8 — 190+ Debian packages from snapshot.debian.org
- Local Bazel registry for submodule resolution (tools/bazel/registry/)
- Native cc_library for swss-common (@sonic_swss_common//:swsscommon) — analysis passes
- Hermetic sysroot with 30+ dev packages
- 89 submodules + 57 docker images with BUILD.bazel
- GH Actions + Cloud Build CI pipelines
- demo.sh with auto-install and submodule sync

## Honest Assessment

What actually works end-to-end:
- 9 hermetic Docker images build in seconds (no Docker daemon)
- Kernel compiles in CI (112 min on GH Actions)
- All Bazel analysis passes (18/18 targets)

What has NOT been verified on real Linux:
- docker-sonic-vs image loads and boots
- pytest passes
- sonic-broadcom.bin assembles with real kernel
- Cloud Build runs successfully
