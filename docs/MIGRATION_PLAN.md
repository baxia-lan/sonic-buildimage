# AGENT.md — SONiC Buildimage: Bazel Migration & Build System Standards

> **Audience:** AI coding agents, contributors, and maintainers working on this migration.
> This document is the single source of truth for development conventions, migration
> strategy, and quality standards for the SONiC build system modernization effort.

---

## Table of Contents

1. [Project Context](#1-project-context)
2. [Repository Map (Current State)](#2-repository-map-current-state)
3. [Migration Roadmap Overview](#3-migration-roadmap-overview)
4. [Phase 1 — Make → Bazel (bzlmod)](#4-phase-1--make--bazel-bzlmod)
5. [Phase 2 — Docker Layer Collapse](#5-phase-2--docker-layer-collapse)
6. [Phase 3 — Dependency Trimming & Image Size Reduction](#6-phase-3--dependency-trimming--image-size-reduction)
7. [CI/CD on GCP](#7-cicd-on-gcp)
8. [Development Conventions](#8-development-conventions)
9. [Verification Protocol](#9-verification-protocol)
10. [Agent Operating Rules](#10-agent-operating-rules)

---

## 1. Project Context

**SONiC (Software for Open Networking in the Cloud)** is a Linux-based open-source
network operating system. This repository (`sonic-buildimage`) is the monorepo build
system that produces:

| Artifact type | Examples | Current toolchain |
|---|---|---|
| ONIE installer image | `sonic-broadcom.bin` (~1 GB) | GNU Make + shell |
| Debian packages (.deb) | 100+ packages | `dpkg-buildpackage` via Make |
| Python wheels (.whl) | platform utilities | `setuptools` via Make |
| Docker images | 58 images, 5-deep layer chain | `docker build` via Make |
| KVM images | `sonic-vs.img` | Make + QEMU tools |

**Key numbers:**
- 48 git submodules
- 25+ hardware platforms
- 3 target architectures: `amd64`, `armhf`, `arm64`
- 609 `.mk` / `.dep` rule files
- Build time: 4-8 hours for a full image on a 32-core machine

**Why migrate?**
The GNU Make system has grown organically for 8+ years. Problems:
- No hermeticity — builds depend on host-installed tools and environment variables
- No incremental builds at artifact level — a change to one `.mk` rebuilds everything
- Opaque dependency tracking via hand-maintained `.dep` files
- Docker-in-Docker build pattern creates unavoidable I/O overhead
- No remote build cache — every CI run pays full rebuild cost
- `sonic-broadcom.bin` at ~1 GB is 3× larger than it needs to be
- Five-layer Docker chain for a single service container is unmaintainable

---

## 2. Repository Map (Current State)

```
sonic-buildimage/
├── Makefile                    # Outer wrapper; selects BLDENV, invokes Docker
├── Makefile.work               # Mid-level orchestrator; spawns sonic-slave container
├── slave.mk                    # Core rules engine inside the build container (1,908 lines)
├── Makefile.cache              # SHA-based cache invalidation layer
├── rules/                      # 327 .mk + 282 .dep rule files (one per artifact)
│   ├── config                  # Feature flags (INCLUDE_P4RT, INCLUDE_ZTP, …)
│   ├── functions               # Make helper functions
│   └── {artifact}.mk/.dep      # Per-artifact build recipe + dependency list
├── dockers/                    # 58 Dockerfiles (Jinja2 .j2 templates)
│   ├── docker-base/            # Layer 1 — minimal Debian base
│   ├── docker-config-engine/   # Layer 2 — Jinja2 config rendering
│   ├── docker-swss-layer/      # Layer 3 — SWSS core libraries
│   └── docker-orchagent/       # Layer 4 — orchestration service (example leaf)
├── src/                        # Submodule sources (48 submodules)
├── platform/                   # Per-platform rules, SAI, kernel modules (25 platforms)
├── device/                     # Per-SKU port configs, EEPROM templates (38 vendors)
├── files/                      # Config templates, init scripts, systemd units
├── scripts/                    # Build helper scripts
└── .azure-pipelines/           # Current CI (Azure DevOps, to be replaced)
```

**Current Docker build chain (example for orchagent):**
```
debian:bookworm                              (upstream, ~120 MB)
  └── sonic-slave-bookworm                   (build env, ~3 GB — only for CI)
  └── docker-base-bookworm                   (runtime base, ~200 MB)
      └── docker-config-engine-bookworm      (+Jinja2 + supervisord, ~250 MB)
          └── docker-swss-layer-bookworm     (+libswsscommon, Redis, +300 MB)
              └── docker-orchagent           (+orchagent binary, +100 MB)
                                             = ~850 MB final image
```

---

## 3. Migration Roadmap Overview

```
Phase 1  Make → Bazel/bzlmod          hermetic, incremental, remote-cacheable
Phase 2  Docker layer collapse         5 layers → 2 layers per service image
Phase 3  Dependency trimming           ~1 GB image → target <400 MB
Parallel CI/CD on GCP                  Cloud Build + Artifact Registry + GCS cache
```

Each phase produces a **self-contained, verified diff** before work begins on the next
phase. Phases 1 and CI run in parallel.

---

## 4. Phase 1 — Make → Bazel (bzlmod)

### 4.1 Guiding Principles

- **Full hermeticity.** Every build input must be declared. No `$(shell date)`, no
  host-installed `apt` packages, no implicit `PATH` lookups.
- **bzlmod only.** Use `MODULE.bazel` + `bazel_dep()`. No `WORKSPACE` file.
  All external dependencies resolved via Bazel Central Registry or `git_override()`.
- **Content-addressed outputs.** All artifacts (`.deb`, `.whl`, OCI layers, final
  `.bin`) are produced by Bazel rules and identified by their content hash.
- **Remote cache first.** Every action must be cacheable with `--remote_cache`.
  No actions write to the source tree.
- **Incremental by default.** A change to one submodule should rebuild only the
  packages that transitively depend on it.

### 4.2 Repository-Level Files to Create

| File | Purpose |
|---|---|
| `MODULE.bazel` | Root module declaration; all `bazel_dep()` calls |
| `.bazelrc` | Shared flags: platforms, remote cache, sandbox settings |
| `.bazelversion` | Pin Bazel version (e.g., `7.4.1`) |
| `BUILD.bazel` | Root package — exposes platform constraints |
| `toolchains/BUILD.bazel` | C/C++, Python, Go toolchain registrations |
| `rules/bazel/` | Custom rule implementations (see §4.4) |

### 4.3 MODULE.bazel Dependencies

```python
module(
    name = "sonic_buildimage",
    version = "0.0.0",
)

# Core infrastructure
bazel_dep(name = "bazel_skylib",        version = "1.7.1")
bazel_dep(name = "platforms",           version = "0.0.10")
bazel_dep(name = "rules_pkg",           version = "1.0.1")

# Language rules
bazel_dep(name = "rules_python",        version = "0.36.0")
bazel_dep(name = "rules_go",            version = "0.50.1")
bazel_dep(name = "rules_rust",          version = "0.52.0")
bazel_dep(name = "rules_cc",            version = "0.0.17")

# OCI / container images (replaces rules_docker)
bazel_dep(name = "rules_oci",           version = "2.0.0")
bazel_dep(name = "container_structure_test", version = "1.19.1")

# Debian package building
bazel_dep(name = "rules_distroless",    version = "0.3.9")  # for minimal base layers
# Custom rules_deb lives in //rules/bazel/deb/

# Toolchains
bazel_dep(name = "toolchains_llvm",     version = "1.2.0")
bazel_dep(name = "hermetic_cc_toolchain", version = "3.1.0")  # musl cross-compile

# Utilities
bazel_dep(name = "aspect_bazel_lib",    version = "2.9.4")
bazel_dep(name = "gazelle",             version = "0.40.0")  # BUILD file generation
```

### 4.4 Custom Bazel Rules Required

All custom rules live under `rules/bazel/`:

#### `rules/bazel/deb/` — Debian package rules

```
deb_package(
    name = "swsscommon",
    srcs = ["//src/sonic-swss-common:all_files"],
    control = "//src/sonic-swss-common:debian/control",
    build_deps = [":libnl3-dev", ":libhiredis-dev"],
    arch = select({
        "//platforms:amd64": "amd64",
        "//platforms:arm64": "arm64",
    }),
)
```

The rule must:
- Run `dpkg-buildpackage` inside a hermetic sandbox with only declared build deps
- Produce deterministic `.deb` files (strip timestamps via `SOURCE_DATE_EPOCH`)
- Support cross-compilation via `--platforms` flag

#### `rules/bazel/oci/` — OCI image rules

Thin wrappers around `rules_oci` that add:
- Automatic `dpkg` installation layer composition
- Supervisord config injection
- Jinja2 template rendering at build time (not at container start)

#### `rules/bazel/onie/` — ONIE installer rules

```
onie_image(
    name = "sonic-broadcom",
    platform = "broadcom",
    rootfs = ":sonic_rootfs_broadcom",
    kernel = "//platform/broadcom:kernel",
    machine = "broadcom",
)
```

#### `rules/bazel/wheel/` — Python wheel rules

Thin wrapper around `rules_python`'s `py_wheel` that handles:
- `sonic-utilities` package conventions
- Platform-specific wheel tags

### 4.5 Platform Constraints

Create `platforms/BUILD.bazel`:
```python
# Architecture constraints
constraint_setting(name = "sonic_arch")
constraint_value(name = "amd64",  constraint_setting = ":sonic_arch")
constraint_value(name = "armhf",  constraint_setting = ":sonic_arch")
constraint_value(name = "arm64",  constraint_setting = ":sonic_arch")

# Platform constraints
constraint_setting(name = "sonic_platform")
constraint_value(name = "broadcom",          constraint_setting = ":sonic_platform")
constraint_value(name = "mellanox",          constraint_setting = ":sonic_platform")
constraint_value(name = "vs",                constraint_setting = ":sonic_platform")
# … one per platform/
```

### 4.6 Submodule Strategy

Each submodule in `src/` gets a `BUILD.bazel` file that exposes:
- Library targets (`.so`, `.a`)
- Header targets (`cc_library(hdrs = …)`)
- Debian package targets via `//rules/bazel/deb:deb_package`

Bazel treats the submodule checkout as a local path — no Bazel module boundary
crossing needed. Use `git_override()` in MODULE.bazel only for external dependencies
that are not already in the BCR.

### 4.7 Migration Sequence (Incremental)

Migrate in dependency order — leaves first, roots last:

```
Week 1-2:   Scaffold MODULE.bazel, .bazelrc, platforms/, toolchains/
            Migrate: libnl, libhiredis, nlohmann_json (no inter-repo deps)

Week 3-4:   Migrate: sonic-swss-common (libswsscommon.deb)
            Migrate: rules_oci base layer (docker-base replacement)

Week 5-6:   Migrate: sonic-sairedis, sonic-swss (depend on swss-common)
            Migrate: docker-config-engine replacement (OCI layer)

Week 7-8:   Migrate: sonic-utilities (Python wheel)
            Migrate: docker-orchagent (full OCI image, Phase 2 target)

Week 9-10:  Migrate: platform/broadcom (sonic-broadcom.bin)
            Enable remote cache on GCP (see §7)

Week 11-12: Migrate remaining 50 Docker images
            Wire Gazelle for auto-BUILD-file maintenance
```

### 4.8 Hermeticity Requirements

- Set `--sandbox_default_allow_network=false` in `.bazelrc`.
- All network access (downloading tarballs, apt) must happen in `repository_rule`s,
  not in build actions.
- Pin all external tarballs with `sha256` integrity hashes.
- Set `SOURCE_DATE_EPOCH = 0` for all packaging actions to ensure reproducibility.
- Use `--incompatible_strict_action_env=true` — no leaking `$HOME`, `$USER`, `$PATH`.

---

## 5. Phase 2 — Docker Layer Collapse

### 5.1 Problem Statement

Current layer chain for orchagent:
```
debian:bookworm (~120 MB)
  + sonic-slave extras (build tools)        ← should not exist in runtime image
  + docker-base (apt packages)              ← merge into single content layer
  + docker-config-engine (supervisord, j2)  ← merge
  + docker-swss-layer (libswsscommon, Redis) ← merge into one shared layer
  + docker-orchagent (orchagent binary)     ← binary layer
```

Each layer adds pull latency, push cost, and maintenance burden.

### 5.2 Target Architecture

With `rules_oci` + `rules_distroless`:

```
gcr.io/distroless/base-debian12 (Google-maintained, <20 MB, no shell)
  └── sonic-common-layer            (supervisord, libssl, libboost — shared across ALL services)
      └── sonic-swss-layer          (libswsscommon + libsairedis — shared by swss-family)
          └── docker-orchagent      (orchagent binary + config only)
```

**Two meaningful layers per service image** (shared + service-specific).

### 5.3 Layer Composition with rules_oci

```python
# //dockers/sonic-common:BUILD.bazel
oci_image(
    name = "sonic_common_layer",
    base = "@distroless_base_debian12",
    tars = [
        ":supervisord_layer",
        ":common_libs_layer",    # libssl, libboost, libprotobuf
        ":redis_client_layer",   # redis-tools, libhiredis
    ],
)

# //dockers/docker-orchagent:BUILD.bazel
oci_image(
    name = "docker_orchagent",
    base = "//dockers/sonic-swss-layer:sonic_swss_layer",
    tars = [
        ":orchagent_binary_layer",
        ":orchagent_config_layer",   # supervisord.conf, start.sh
    ],
    labels = {"org.opencontainers.image.source": "…"},
)
```

### 5.4 Jinja2 Template Rendering

Currently templates are rendered at container start by `docker-config-engine`.
Move rendering to **build time**:

```python
# rules/bazel/j2/render.bzl
def j2_render(name, template, vars_file, output):
    """Render a Jinja2 template at Bazel build time."""
    native.genrule(
        name = name,
        srcs = [template, vars_file],
        outs = [output],
        cmd = "$(location //tools:j2cli) $< --undefined strict -o $@",
        tools = ["//tools:j2cli"],
    )
```

Config that truly needs runtime values (e.g., interface IPs) stays rendered at
runtime but uses a minimal Python script, not the full `docker-config-engine` image.

### 5.5 supervisord Configuration

Replace per-image supervisord build with a shared `//files/supervisord:base.conf`
that each image extends with `[include]` directives.

---

## 6. Phase 3 — Dependency Trimming & Image Size Reduction

### 6.1 Target: sonic-broadcom.bin < 400 MB

Current size breakdown (approximate):
```
Linux kernel + initrd               ~80 MB   (keep, trim modules)
Docker runtime                      ~60 MB   (keep)
All service container tarballs      ~500 MB  (primary target)
Platform kernel modules             ~80 MB   (platform-specific, trim)
Python + utilities                  ~120 MB  (trim)
frr (routing)                       ~60 MB   (trim)
Misc packages                       ~100 MB  (audit)
Total                               ~1 GB
```

### 6.2 Elimination Targets

**Definitely removable:**
- Debug symbols in all packages: strip via `dh_strip --no-automatic-dbgsym`
- `man` pages, `doc` directories: add `dpkg` excludes
- `locales` (non-en): add `LANG=C` and `locales-all` → `locales` swap
- Python 2 (`python2.7`, `python-*`): fully removed in bookworm target
- `perl` (required by some postinst scripts): audit and patch postinst scripts
- `bash-doc`, `vim-common`, `wget` (present in some images): audit per image

**Kernel module trimming:**
Only load modules actually used by the target platform. Use a `modules.dep`
allowlist per SKU. This alone can save 20-40 MB.

**frr binary optimization:**
Build frr with `--disable-doc --disable-grpc` and strip debug. Target: ~35 MB.

### 6.3 Bazel Integration

Use `rules_pkg`'s `pkg_tar` with explicit file inclusion:
```python
pkg_tar(
    name = "orchagent_binary_layer",
    srcs = [":orchagent_stripped"],   # cc_binary with strip_debug = True
    include_runfiles = False,
    mode = "0755",
    package_dir = "/usr/bin",
)
```

Always use `strip = True` or `cc_binary(... strip = "always")` for release builds.

### 6.4 Dependency Audit Protocol

Before removing any package:
1. Run `ldd <binary>` against all binaries in the image to confirm no runtime link.
2. Run the container's health check and functional smoke test.
3. Record the package name in `docs/removed_deps.md` with justification.
4. The Bazel `deb_package` rule must declare only the packages that `ldd` confirms
   are actually needed (no `Recommends`, no `Suggests`).

---

## 7. CI/CD on GCP

### 7.1 Architecture

```
GitHub (source)
  │
  ├─▶ Cloud Build trigger (push / PR)
  │     ├─▶ Bazel build with --remote_cache=grpcs://${REMOTE_CACHE_URL}
  │     ├─▶ Bazel test
  │     └─▶ Artifact push to Artifact Registry
  │
  ├─▶ Cloud Build trigger (nightly / release)
  │     └─▶ Full platform image builds (broadcom, mellanox, vs)
  │
  └─▶ GKE (test cluster)
        └─▶ VS platform smoke test (sonic-vs.img on QEMU)
```

### 7.2 Remote Cache (GCS)

```ini
# .bazelrc additions for CI
build:ci --remote_cache=grpcs://remotebuildexecution.googleapis.com
build:ci --google_default_credentials
build:ci --remote_instance_name=projects/${PROJECT_ID}/instances/sonic-cache
build:ci --remote_upload_local_results
build:ci --jobs=64
```

Use a `gs://sonic-bazel-cache` GCS bucket with:
- 30-day lifecycle for action cache entries
- Public read for cache hits (speeds up contributor builds)
- Write access restricted to CI service account

### 7.3 Cloud Build Configuration

`cloudbuild.yaml` (root):
```yaml
steps:
  - name: gcr.io/cloud-builders/bazel
    args:
      - build
      - --config=ci
      - --platforms=//platforms:amd64
      - //dockers/docker-orchagent:docker_orchagent
      - //platform/vs:sonic-vs
    env:
      - BAZEL_REMOTE_CACHE_URL=${_REMOTE_CACHE_URL}

  - name: gcr.io/cloud-builders/bazel
    args:
      - test
      - --config=ci
      - //...
    env:
      - BAZEL_REMOTE_CACHE_URL=${_REMOTE_CACHE_URL}

images:
  - us-central1-docker.pkg.dev/${PROJECT_ID}/sonic/docker-orchagent:${SHORT_SHA}
```

### 7.4 Availability Design

- **Multi-region triggers:** Cloud Build pools in `us-central1` and `us-east1`.
  If one region is degraded, the other picks up PR builds automatically.
- **GCS cache replication:** Multi-region bucket (`us`) for cache reads.
- **Artifact Registry:** Multi-region repository for final images.
- **Build timeout:** Set `timeout: 3600s` per step; full builds split across
  parallel steps by artifact type.
- **Quotas:** Request elevated concurrent build quotas (≥20 concurrent builds)
  for large PRs against the monorepo.

### 7.5 Migration from Azure Pipelines

Keep `.azure-pipelines/` files until GCP CI is validated for ≥30 days.
Run both in parallel; require both to pass before merge during transition.

---

## 8. Development Conventions

### 8.1 Bazel File Style

- One `BUILD.bazel` file per directory (not per file).
- All `BUILD.bazel` files must be formatted with `buildifier`.
- Target names use `lower_snake_case`.
- Public targets (used outside the package) are listed in `package(default_visibility
  = ["//visibility:public"])` only when necessary; default to `//visibility:private`.
- Never use `glob()` for source files that can be listed explicitly.
- `select()` expressions for architecture/platform go at the bottom of the target.

### 8.2 Debian Package Rules

- Every `.deb` produced by this build must declare all `Build-Depends` in the
  Bazel rule, not just in `debian/control` (both must be kept in sync).
- Use `deb_package_set()` to group related packages from one source tree.
- Always set `SOURCE_DATE_EPOCH = $(date -d "$(git log -1 --format=%ci HEAD)" +%s)`
  in the rule to produce reproducible packages.

### 8.3 OCI Image Rules

- Base image digests must be pinned (e.g., `@sha256:abc123…`), never by mutable tag.
- Use `oci_push` targets only in CI, never locally.
- All images must have a `container_structure_test` target adjacent to them.
- Image labels must include `org.opencontainers.image.revision` = git SHA.

### 8.4 Commit Convention

```
<type>(<scope>): <subject>

type:  feat | fix | refactor | build | ci | docs | test | chore
scope: bazel | deb | oci | onie | platform/<name> | rules | ci
```

Example: `build(bazel): add deb_package rule for libswsscommon`

### 8.5 Branch and PR Strategy

- All work on `claude` branch (this branch) during migration.
- Each phase milestone gets a PR to `master` once verified.
- PRs must include a verification checklist (see §9).
- No force-push to `master`. Rebase before merge.

### 8.6 File Organization (Target State)

```
sonic-buildimage/
├── MODULE.bazel
├── .bazelrc
├── .bazelversion
├── BUILD.bazel
├── platforms/
│   └── BUILD.bazel          (constraint definitions)
├── toolchains/
│   └── BUILD.bazel          (cc, python, go toolchains)
├── rules/
│   ├── bazel/
│   │   ├── deb/             (deb_package rule)
│   │   ├── oci/             (sonic_oci_image rule)
│   │   ├── onie/            (onie_image rule)
│   │   ├── wheel/           (sonic_wheel rule)
│   │   └── j2/              (j2_render rule)
│   └── [legacy .mk files — kept until fully replaced]
├── src/                     (submodules — each gets BUILD.bazel)
├── dockers/                 (each gets BUILD.bazel)
├── platform/                (each platform gets BUILD.bazel)
├── cloudbuild.yaml          (GCP Cloud Build)
└── AGENT.md                 (this file)
```

---

## 9. Verification Protocol

Every change must be verified before being considered complete. Do not mark a task
done without running the relevant checks.

### 9.1 Bazel Build Verification

```bash
# 1. Format all BUILD files
bazel run //:buildifier

# 2. Build the target under test
bazel build //path/to:target --sandbox_debug

# 3. Verify hermeticity (no undeclared inputs)
bazel build //path/to:target --experimental_repo_remote_exec
# Must complete with no "missing input file" warnings

# 4. Verify reproducibility (build twice, compare outputs)
bazel build //path/to:target --output_base=/tmp/build1
bazel clean --expunge
bazel build //path/to:target --output_base=/tmp/build2
diff -r /tmp/build1/execroot/sonic_buildimage/bazel-out \
         /tmp/build2/execroot/sonic_buildimage/bazel-out

# 5. Verify remote cache (must be a cache hit on second run)
bazel build //path/to:target --remote_cache=${CACHE_URL} --verbose_failures
```

### 9.2 Docker Image Verification

```bash
# 1. Build OCI image with Bazel
bazel build //dockers/docker-orchagent:docker_orchagent.tar

# 2. Load and inspect
docker load < bazel-bin/dockers/docker-orchagent/docker_orchagent.tar
docker inspect sonic/docker-orchagent:latest | jq '.[0].RootFS.Layers | length'
# Must be <= 3 layers

# 3. Size check
docker image ls sonic/docker-orchagent --format "{{.Size}}"
# Must be <= target size from §6.1 per-image budget

# 4. Structure test
bazel test //dockers/docker-orchagent:structure_test

# 5. Functional smoke test (for VS platform)
bazel run //platform/vs:sonic_vs_smoke_test
```

### 9.3 ONIE Image Verification

```bash
# 1. Build
bazel build //platform/broadcom:sonic-broadcom --platforms=//platforms:amd64

# 2. Size check
du -sh bazel-bin/platform/broadcom/sonic-broadcom.bin
# Must be <= 400 MB (Phase 3 target)

# 3. ONIE signature check
bash scripts/verify_onie_image.sh bazel-bin/platform/broadcom/sonic-broadcom.bin

# 4. KVM boot test (VS image equivalent)
bazel test //platform/vs:boot_test --test_timeout=300
```

### 9.4 Dependency Verification

```bash
# For any new deb_package rule:
# 1. Extract package and run ldd on all ELF binaries
dpkg-deb -x <package>.deb /tmp/pkg_extract
find /tmp/pkg_extract -type f -executable | xargs -I{} ldd {} 2>/dev/null \
  | grep "not found"
# Must produce no output (all shared libs resolvable)

# 2. Confirm package size delta
dpkg-deb -I <package>.deb | grep Installed-Size
```

### 9.5 CI Verification

Before merging any Phase milestone PR:
- [ ] Cloud Build runs green on the PR branch
- [ ] Build time is ≤ previous baseline (no regression)
- [ ] Remote cache hit rate ≥ 80% on re-run of same commit
- [ ] No new packages added to base image without documented justification
- [ ] `bazel query 'deps(//...)' | wc -l` does not increase without explanation

---

## 10. Agent Operating Rules

These rules govern how AI agents (including Claude) must behave when working in
this repository. They are non-negotiable.

### Read Before Writing
Always read the current state of a file before editing it. Never assume file
contents from memory. Check file existence before writing.

### Verify After Every Change
After writing or editing any Bazel file, run the relevant build command and confirm
it succeeds. Do not mark a task complete without successful verification output.

### No Speculative Abstractions
Do not create helper rules, macros, or wrapper targets "for future use." Build
exactly what is needed by the current task. Three explicit `deb_package()` calls
are better than an untested `deb_package_group()` macro.

### Incremental Migration
Do not attempt to migrate all 609 `.mk` files at once. Migrate one submodule or
one Docker image at a time, verify it, then proceed. The Make system remains
functional and authoritative until a Bazel target is verified to produce an
identical artifact.

### Hermeticity is Non-Negotiable
If a build action requires `network = True` or touches files outside its declared
inputs, that is a bug. Fix it before proceeding. Never use `--noincompatible_strict_action_env`
as a workaround.

### Preserve Make System During Transition
Do not delete or modify `.mk` files, `slave.mk`, or `Makefile.work` until the
corresponding Bazel target has been verified end-to-end including CI. The old
system is the reference; the new system must match its outputs.

### Size Budget Enforcement
Every OCI image and ONIE binary has a size budget defined in §6.1. If a change
causes a size regression, it must be justified and approved before merging.

### Document Every Removed Dependency
When removing any package from an image, write an entry to `docs/removed_deps.md`
with: package name, images affected, why it was safe to remove, and how it was
verified.

### Commit Atomically
Each commit should be a single logical change: one new BUILD file, one rule
implementation, one Docker image migration. Do not bundle unrelated changes.

---

*Last updated: 2026-04-01*
*Branch: claude*
*Status: Phase 1 scaffold in progress*
