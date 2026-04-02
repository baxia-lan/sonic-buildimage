# SONiC Build System — Bazel Migration Guide

> This document covers the new Bazel-based build system, how to verify it,
> hermeticity guarantees, and how it replaces the legacy Make system.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Quick Start](#3-quick-start)
4. [Build Targets Reference](#4-build-targets-reference)
5. [Hermeticity](#5-hermeticity)
6. [bzlmod Dependency Management](#6-bzlmod-dependency-management)
7. [Custom Bazel Rules](#7-custom-bazel-rules)
8. [Docker Layer Architecture](#8-docker-layer-architecture)
9. [Size Budget Enforcement](#9-size-budget-enforcement)
10. [Verification Guide](#10-verification-guide)
11. [CI/CD Pipeline](#11-cicd-pipeline)
12. [Cross-Compilation](#12-cross-compilation)
13. [Troubleshooting](#13-troubleshooting)
14. [Migration Status](#14-migration-status)

---

## 1. Architecture Overview

The build system has been migrated from GNU Make (`slave.mk` + 327 `rules/*.mk`
files) to Bazel 7.4.1 with bzlmod. The migration covers three layers:

```
MODULE.bazel                    ← root module, all external deps declared here
├── src/*/BUILD.bazel           ← 36 submodule packages (.deb, .whl)
├── dockers/*/BUILD.bazel       ← 26 OCI service container images
├── platform/*/BUILD.bazel      ← platform installer images (.bin, .swi)
├── rules/bazel/
│   ├── deb/deb.bzl             ← debian_source_package(), deb_package_set()
│   ├── oci/oci.bzl             ← sonic_oci_image(), sonic_service_image()
│   ├── oci/strip_layer.bzl     ← stripped_layer() — debug strip + size budget
│   ├── onie/onie.bzl           ← onie_image(), sonic_rootfs()
│   ├── onie/module_filter.bzl  ← filtered_modules() — kernel module allowlist
│   ├── wheel/wheel.bzl         ← sonic_wheel() — Python wheel builder
│   └── j2/j2.bzl               ← j2_render() — build-time Jinja2 rendering
└── .bazelrc                    ← hermeticity flags, CI config, cross-compile configs
```

**Key design decisions:**

| Decision | Rationale |
|---|---|
| bzlmod only (no WORKSPACE) | Transitive dependency resolution, version selection, reproducible fetches |
| distroless base images | ~20 MB vs ~200 MB for debian:bullseye — no shell, no apt at runtime |
| ≤3 OCI layers per image | Reduces pull time, simplifies debugging, enforces modularity |
| `SOURCE_DATE_EPOCH=0` everywhere | Bit-for-bit reproducible builds regardless of build time |
| Size budgets as build rules | Build *fails* if any layer exceeds its budget — not just a warning |

### Build Target Count

| Area | BUILD.bazel files | Bazel targets |
|---|---|---|
| `src/` (packages) | 36 | 97 |
| `dockers/` (OCI images) | 26 | 414 |
| `platform/` (installers) | 3 | 22 |
| Other (tools, rules, etc.) | 16 | 38 |
| **Total** | **81** | **571** |

---

## 2. Prerequisites

### Required

| Tool | Version | Install |
|---|---|---|
| Bazelisk | ≥1.19 | `brew install bazelisk` or [GitHub releases](https://github.com/bazelbuild/bazelisk/releases) |
| Git | ≥2.30 | System package manager |
| Docker | ≥24.0 | Required for genrule actions that run inside containers |
| Python | 3.11+ | For j2cli and test tooling |

Bazelisk reads `.bazelversion` and auto-downloads Bazel 7.4.1.

### Optional (for full platform builds)

| Tool | Purpose |
|---|---|
| `gcloud` CLI | GCP Cloud Build, remote cache |
| `crane` | Refresh OCI base image digests |
| `debdiff` | Output equivalence checks vs Make |
| `buildifier` | Starlark formatting (`bazel run //:buildifier_check`) |

### Submodule Initialization

```bash
# Clone with submodules
git clone --recurse-submodules -b claude git@github.com:baxia-lan/sonic-buildimage.git
cd sonic-buildimage

# Or if already cloned:
git submodule update --init --recursive
```

All 48 submodules are forked to `baxia-lan/*` with `branch=claude` in
`.gitmodules`. Each fork has its own `BUILD.bazel`.

---

## 3. Quick Start

### Validate BUILD files parse correctly

```bash
# This is the fastest way to verify the build system is structurally sound.
# No compilation happens — just loads and parses all BUILD files.
bazel query '//...'
# Expected: 571 targets, 0 errors
```

### Build a single package (leaf dependency)

```bash
bazel build //src/libnl3:libnl3_debs --sandbox_debug
```

### Build a Docker image

```bash
# Build the orchagent OCI image
bazel build //dockers/docker-orchagent:docker_orchagent

# Export as docker-loadable tarball
bazel build //dockers/docker-orchagent:docker_orchagent_tarball

# Load into local Docker
docker load -i $(bazel cquery --output=files //dockers/docker-orchagent:docker_orchagent_tarball)
docker images | grep orchagent
```

### Build a platform installer

```bash
# Virtual Switch (for development/testing)
bazel build //platform/vs:sonic_vs_bin

# Broadcom ONIE installer
bazel build //platform/broadcom:sonic_broadcom_bin

# Broadcom Aboot (Arista SWI format)
bazel build //platform/broadcom/sonic-aboot:sonic_aboot_broadcom_swi
```

### Build everything

```bash
bazel build //...
```

---

## 4. Build Targets Reference

### Debian Packages (`src/`)

| Target | Package | Type |
|---|---|---|
| `//src/libnl3:libnl3_debs` | libnl3 3.7.0 | `debian_source_package` |
| `//src/sonic-swss-common:swss_common_debs` | libswsscommon 1.0.0 | `deb_package_set` |
| `//src/sonic-sairedis:sairedis_debs` | libsairedis 1.0.0 | `deb_package_set` |
| `//src/sonic-swss:swss_debs` | swss 1.0.0 | `deb_package_set` |
| `//src/sonic-frr:frr_debs` | FRR 10.5.1 | `deb_package_set` |
| `//src/snmpd:snmpd_debs` | Net-SNMP 5.9.3 | `deb_package_set` |

Convenience aliases: `//src/sonic-swss-common:swss_common`, `:swss_common_dev`,
`:python3_swsscommon`, `:sonic_db_cli`.

### Python Wheels (`src/`)

| Target | Distribution | Version |
|---|---|---|
| `//src/sonic-utilities:sonic_utilities_wheel` | sonic-utilities | 1.2 |
| `//src/sonic-host-services:sonic_host_services_wheel` | sonic-host-services | 1.0 |
| `//src/sonic-platform-common:sonic_platform_common_wheel` | sonic-platform-common | 1.0 |
| `//src/sonic-py-swsssdk:swsssdk_wheel` | swsssdk | 2.0.1 |
| `//src/sonic-dbsyncd:dbsyncd_wheel` | sonic-dbsyncd | 2.0.0 |

### OCI Images (`dockers/`)

| Target | Base Layer | Services |
|---|---|---|
| `//dockers/sonic-common-layer:sonic_common_layer` | distroless/base-debian12 | supervisord, redis-tools, rsyslog |
| `//dockers/docker-swss-layer-bullseye:sonic_swss_layer_bullseye` | sonic-common-layer | libswsscommon, libsairedis |
| `//dockers/docker-orchagent:docker_orchagent` | sonic-swss-layer | orchagent binary |
| `//dockers/docker-database:docker_database` | sonic-common-layer | redis-server, sonic-db-cli |
| `//dockers/docker-fpm-frr:docker_fpm_frr` | sonic-swss-layer | FRR routing suite |
| `//dockers/docker-snmp:docker_snmp` | sonic-common-layer | snmpd, sonic-snmpagent |
| `//dockers/docker-sonic-gnmi:docker_sonic_gnmi` | sonic-common-layer | gNMI server |

Every OCI image also produces a `_tarball` target for `docker load`:
```bash
bazel build //dockers/docker-database:docker_database_tarball
```

### Platform Images (`platform/`)

| Target | Output | Format |
|---|---|---|
| `//platform/vs:sonic_vs_bin` | sonic-vs.bin | ONIE installer |
| `//platform/vs:docker_sonic_vs` | docker-sonic-vs | OCI (all-in-one) |
| `//platform/broadcom:sonic_broadcom_bin` | sonic-broadcom.bin | ONIE installer |
| `//platform/broadcom/sonic-aboot:sonic_aboot_broadcom_swi` | sonic-aboot-broadcom.swi | Arista SWI |

---

## 5. Hermeticity

The build is hermetic by design. Every build action runs in a sandboxed
environment with no access to the host filesystem or network.

### Enforced in `.bazelrc`

```
build --incompatible_strict_action_env=true    # No inherited env vars
build --sandbox_default_allow_network=false     # No network in build actions
build --action_env=SOURCE_DATE_EPOCH=0          # Reproducible timestamps
build --action_env=HOME=/nonexistent            # No home dir access
build --action_env=USER=bazel                   # No real user identity
build --spawn_strategy=sandboxed                # Sandboxed execution
```

### What this means in practice

| Guarantee | How it's enforced |
|---|---|
| **No host tools leak** | `--incompatible_strict_action_env` clears the environment; only explicitly declared `action_env` values are visible |
| **No network in builds** | `--sandbox_default_allow_network=false` blocks all network access. External sources are fetched in `repository_rule`s *before* the build phase |
| **Reproducible timestamps** | `SOURCE_DATE_EPOCH=0` + `tar --mtime=@0 --sort=name --owner=0 --group=0` produce identical tarballs regardless of build time |
| **Pinned external deps** | All tarballs in `MODULE.bazel` have `sha256` checksums. OCI base images are pinned by `sha256` digest, never by mutable tag |
| **No submodule mutations** | Submodule state must be pinned *before* `bazel build`. No `git submodule update` runs inside any build action |

### Network access boundary

```
repository_rule (MODULE.bazel)     ← network allowed (fetches source archives)
         │
         ▼
build action (BUILD.bazel)         ← network BLOCKED (sandbox enforced)
         │
         ▼
test action (BUILD.bazel)          ← network BLOCKED (sandbox enforced)
```

### Reproducibility verification

Two consecutive clean builds must produce bit-identical output:

```bash
# Build 1
bazel clean --expunge
bazel build //src/libnl3:libnl3_debs
sha256sum bazel-out/*/bin/src/libnl3/*.deb > /tmp/build1.sha

# Build 2
bazel clean --expunge
bazel build //src/libnl3:libnl3_debs
sha256sum bazel-out/*/bin/src/libnl3/*.deb > /tmp/build2.sha

# Compare
diff /tmp/build1.sha /tmp/build2.sha
# Expected: no differences
```

---

## 6. bzlmod Dependency Management

The build uses **bzlmod exclusively** — there is no `WORKSPACE` file. All
external dependencies are declared in `MODULE.bazel`.

### How bzlmod works

```python
# MODULE.bazel — root module declaration
module(name = "sonic_buildimage", version = "0.0.0")

# External rule sets as bazel_dep()
bazel_dep(name = "rules_oci",     version = "2.0.0")
bazel_dep(name = "rules_pkg",     version = "1.0.1")
bazel_dep(name = "rules_python",  version = "0.36.0")
bazel_dep(name = "rules_go",      version = "0.50.1")
bazel_dep(name = "rules_cc",      version = "0.0.17")
bazel_dep(name = "rules_foreign_cc", version = "0.13.0")

# OCI base images (pinned by sha256 digest)
oci = use_extension("@rules_oci//oci:extensions.bzl", "oci")
oci.pull(
    name = "distroless_base_debian12",
    digest = "sha256:cc47d4cd0f85...",   # NEVER a mutable tag
    image = "gcr.io/distroless/base-debian12",
)

# Python toolchain
python = use_extension("@rules_python//python/extensions:python.bzl", "python")
python.toolchain(python_version = "3.11")

# Go SDK
go_sdk = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
go_sdk.download(version = "1.23.3")
```

### Why bzlmod over WORKSPACE

| WORKSPACE (legacy) | bzlmod (this project) |
|---|---|
| Manual transitive dependency management | Automatic version resolution |
| `http_archive()` with ad-hoc names | `bazel_dep()` with semantic versioning |
| Order-dependent evaluation | Declarative, order-independent |
| No diamond dependency resolution | MVS (minimum version selection) resolves conflicts |
| `.bazelrc` flag: N/A | `--enable_bzlmod` (default in Bazel 7+) |

### Adding a new external dependency

```python
# 1. Add to MODULE.bazel:
bazel_dep(name = "rules_foo", version = "1.2.3")

# 2. Run:
bazel mod tidy

# 3. The lockfile (MODULE.bazel.lock) is auto-updated.
```

### Refreshing OCI base image digests

```bash
# Get the latest digest:
crane digest gcr.io/distroless/base-debian12:latest

# Update MODULE.bazel:
oci.pull(
    name = "distroless_base_debian12",
    digest = "sha256:<new_digest>",
    ...
)
```

---

## 7. Custom Bazel Rules

### `debian_source_package()` — Upstream Debian packages

For packages fetched from the Debian pool (dsc + orig.tar.gz + patches):

```python
load("//rules/bazel/deb:deb.bzl", "debian_source_package")

debian_source_package(
    name = "libnl3_debs",
    dsc = "@libnl3_source//:dsc",
    srcs = ["@libnl3_source//:orig_tar", "@libnl3_source//:debian_tar"],
    version = "3.7.0-0.2+b1sonic1",
    patches = [":patches"],
    declared_outputs = ["libnl-3-200_*.deb", "libnl-3-dev_*.deb"],
)
```

### `deb_package_set()` — In-tree submodule packages

For packages in `src/` that have a `debian/` directory:

```python
load("//rules/bazel/deb:deb.bzl", "deb_package_set")

deb_package_set(
    name = "swss_common_debs",
    srcs = glob(["**/*"], exclude = [".git/**", "BUILD.bazel"]),
    debian_dir = "debian",
    version = "1.0.0",
    build_deps = ["//src/libnl3:libnl3_dev"],
    declared_outputs = ["libswsscommon_1.0.0_$(ARCH).deb"],
)
```

### `sonic_wheel()` — Python wheels

```python
load("//rules/bazel/wheel:wheel.bzl", "sonic_wheel")

sonic_wheel(
    name = "sonic_utilities_wheel",
    distribution = "sonic-utilities",
    version = "1.2",
    deps = ["//src/sonic-platform-common:sonic_platform_common_wheel"],
)
```

### `sonic_oci_image()` — OCI container images

```python
load("//rules/bazel/oci:oci.bzl", "sonic_oci_image")

sonic_oci_image(
    name = "docker_orchagent",
    base = "//dockers/docker-swss-layer-bullseye:sonic_swss_layer_bullseye",
    tars = [":orchagent_apt_layer_stripped", ":orchagent_binary_layer_stripped"],
    labels = {"org.opencontainers.image.title": "docker-orchagent"},
)
```

### `stripped_layer()` — Size enforcement + debug stripping

```python
load("//rules/bazel/oci:strip_layer.bzl", "stripped_layer")

stripped_layer(
    name = "orchagent_apt_layer_stripped",
    src = ":orchagent_apt_layer",
    size_budget_mb = 40,    # BUILD FAILS if layer exceeds 40 MB
)
```

What `stripped_layer()` does:
1. Strips debug symbols from all `.so*` and ELF binaries
2. Removes `/usr/share/man`, `/usr/share/doc`, `/usr/share/locale`, `/usr/share/i18n`
3. Removes Python `__pycache__/` and `.pyc` files
4. Removes apt caches and dpkg status files
5. Produces deterministic tar (`SOURCE_DATE_EPOCH=0`, sorted, `--owner=0`)
6. **Fails the build** if output exceeds `size_budget_mb`

### `filtered_modules()` — Kernel module allowlist

```python
load("//rules/bazel/onie:module_filter.bzl", "filtered_modules")

filtered_modules(
    name = "broadcom_modules",
    modules_tar = "//src/sonic-linux-kernel:kernel_modules_tar",
    allowlist = "//platform/broadcom:modules.allowlist",
    size_budget_mb = 60,
)
```

### `j2_render()` — Build-time Jinja2 rendering

Replaces docker-config-engine's runtime template rendering:

```python
load("//rules/bazel/j2:j2.bzl", "j2_render")

j2_render(
    name = "supervisord_conf",
    template = "supervisord.conf.j2",
    vars = "//files/build_vars:orchagent.json",
    output = "supervisord.conf",
)
```

### `onie_image()` — ONIE installer assembly

```python
load("//rules/bazel/onie:onie.bzl", "onie_image")

onie_image(
    name = "sonic_broadcom_bin",
    rootfs = ":sonic_broadcom_rootfs",
    kernel = "//src/sonic-linux-kernel:vmlinuz",
    platform_modules = [":broadcom_modules"],
    platform = "broadcom",
    machine = "x86_64-broadcom_common",
    version = "0.0.0-bazel",
)
```

---

## 8. Docker Layer Architecture

### Before (Make system — 5-deep chain)

```
debian:bullseye                         ~200 MB
└── docker-base-bullseye                +~100 MB  (perl, vim, apt, pip)
    └── docker-config-engine-bullseye   +~80 MB   (j2, supervisord, python pkgs)
        └── docker-swss-layer-bullseye  +~300 MB  (libswsscommon, build-essential)
            └── docker-orchagent        +~50 MB   (orchagent binary)
Total: ~730 MB per service image
```

### After (Bazel system — 3 layers max)

```
gcr.io/distroless/base-debian12         ~20 MB   (no shell, no apt)
└── sonic-common-layer                  ≤150 MB  (supervisord, redis-tools, rsyslog)
    └── docker-orchagent                ≤80 MB   (orchagent + runtime apt deps)
Total: ~250 MB per service image
```

For swss-family images (orchagent, teamd, nat, sflow, macsec, fpm-frr):

```
distroless/base-debian12                 ~20 MB
└── sonic-common-layer                  ≤150 MB
    └── sonic-swss-layer                ≤140 MB  (libswsscommon + libsairedis)
        └── docker-orchagent            ≤80 MB
Total: ~390 MB (under 400 MB budget)
```

### What was removed

| Removed | Why | Savings |
|---|---|---|
| `build-essential`, `python3-dev` | Build-time only; never needed at runtime | ~100 MB |
| `perl` | Only needed for dpkg postinst; no dpkg at runtime | ~15 MB |
| `vim-tiny` | Debug tool; use exec into debug image instead | ~5 MB |
| `python3-pip` | All packages installed at build time | ~10 MB |
| `apt`, `apt-utils` | No package installation at runtime | ~30 MB |
| `exim4` | Was an rsyslog Recommends; blocked by `--no-install-recommends` | ~15 MB |
| `docker-config-engine` layer | Jinja2 rendering moved to build time via `j2_render()` | ~80 MB |
| Debug symbols | Stripped by `stripped_layer()` | ~50 MB |
| Man pages, docs, locale | Excluded by dpkg path-exclude | ~30 MB |

Full removal log: `docs/removed_deps.md`.

---

## 9. Size Budget Enforcement

Size budgets are enforced at build time — the build **fails** if any layer
or artifact exceeds its budget. This is not a post-build check.

### Per-Layer Budgets

| Layer | Budget | Enforced by |
|---|---|---|
| `sonic-common-layer` | ≤ 150 MB | `stripped_layer(size_budget_mb = 150)` |
| `libswsscommon_layer` | ≤ 80 MB | `stripped_layer(size_budget_mb = 80)` |
| `libsairedis_layer` | ≤ 60 MB | `stripped_layer(size_budget_mb = 60)` |
| `orchagent_apt_layer` | ≤ 40 MB | `stripped_layer(size_budget_mb = 40)` |
| `orchagent_binary_layer` | ≤ 30 MB | `stripped_layer(size_budget_mb = 30)` |
| Broadcom filtered modules | ≤ 60 MB | `filtered_modules(size_budget_mb = 60)` |

### Per-Artifact Budgets

| Artifact | Budget | Enforced by |
|---|---|---|
| `sonic-broadcom.bin` | ≤ 400 MB | `onie_image_builder.sh` + `cloudbuild-nightly.yaml` |
| `sonic-aboot-broadcom.swi` | ≤ 400 MB | genrule size check |
| Any single OCI image | ≤ 300 MB | `cloudbuild.yaml` step |
| Any `.deb` vs Make baseline | 0 MB growth | `debdiff` in CI |

### How it works

```bash
# stripped_layer() runs this at the end of every layer build:
SIZE_MB=$(( $(stat -c%s output.tar) / 1048576 ))
if [ "$SIZE_MB" -gt $BUDGET ]; then
  echo "FAIL: layer is $SIZE_MB MB, exceeds $BUDGET MB budget"
  exit 1    # <-- build fails here
fi
```

---

## 10. Verification Guide

### Level 1: Syntax verification (instant)

Confirms all BUILD files parse correctly and the dependency graph is valid.

```bash
# Parse all BUILD files — should return 571 targets, 0 errors
bazel query '//...'

# Verify dependency graph for a specific target
bazel query 'deps(//dockers/docker-orchagent:docker_orchagent)' | head -30

# Check reverse dependencies (what depends on swss-common)
bazel query 'rdeps(//..., //src/sonic-swss-common:swss_common_debs)'

# Verify no circular dependencies
bazel query 'somepath(//src/sonic-swss:swss_debs, //src/libnl3:libnl3_debs)'
```

### Level 2: Build verification (requires Docker + sonic-slave)

```bash
# Build a leaf package
bazel build //src/libnl3:libnl3_debs --sandbox_debug

# Build a mid-level package (tests dependency chain)
bazel build //src/sonic-swss-common:swss_common_debs --sandbox_debug

# Build a Docker image
bazel build //dockers/docker-orchagent:docker_orchagent

# Build everything
bazel build //...
```

### Level 3: Output equivalence (Make vs Bazel)

```bash
# Build with Make (legacy)
make target/debs/bullseye/libswsscommon_1.0.0_amd64.deb

# Build with Bazel
bazel build //src/sonic-swss-common:swss_common_debs

# Compare
debdiff \
  target/debs/bullseye/libswsscommon_1.0.0_amd64.deb \
  bazel-out/k8-fastbuild/bin/src/sonic-swss-common/libswsscommon_1.0.0_amd64.deb

# Only timestamp differences are acceptable
```

### Level 4: OCI image verification

```bash
# Build and load the image
bazel build //dockers/docker-orchagent:docker_orchagent_tarball
docker load -i $(bazel cquery --output=files //dockers/docker-orchagent:docker_orchagent_tarball)

# Check layer count (must be ≤ 3)
docker inspect sonic/docker_orchagent:dev | jq '.[0].RootFS.Layers | length'

# Check image size
docker image inspect sonic/docker_orchagent:dev --format='{{.Size}}' \
  | awk '{printf "%.0f MB\n", $1/1048576}'

# Verify no shell (distroless)
docker run --rm sonic/docker_orchagent:dev /bin/sh 2>&1 | grep "not found"
# Expected: exec /bin/sh: not found

# Verify supervisord starts
docker run --rm sonic/docker_orchagent:dev &
sleep 2
docker exec <container_id> supervisorctl status
```

### Level 5: Reproducibility verification

```bash
# Build twice from clean state, compare checksums
for i in 1 2; do
  bazel clean --expunge
  bazel build //dockers/docker-orchagent:docker_orchagent_tarball
  sha256sum $(bazel cquery --output=files \
    //dockers/docker-orchagent:docker_orchagent_tarball)
done
# Both sha256 values must be identical
```

### Level 6: Platform image verification

```bash
# Build the VS ONIE installer
bazel build //platform/vs:sonic_vs_bin

# Check size
ls -lh bazel-out/*/bin/platform/vs/sonic_vs_bin.bin

# Build broadcom installer and verify size budget
bazel build //platform/broadcom:sonic_broadcom_bin
SIZE=$(stat -f%z bazel-out/*/bin/platform/broadcom/sonic_broadcom_bin.bin)
echo "$((SIZE / 1048576)) MB"   # Must be ≤ 400 MB
```

---

## 11. CI/CD Pipeline

### PR Pipeline (`cloudbuild.yaml`)

Runs on every push and PR. Fast (< 40 minutes).

```
Step 0: Pull Bazel image
Step 1: buildifier format check          ← fail fast on formatting
Step 2: Bazel build (amd64 targets)      ← builds all migrated targets
Step 3: OCI tarball export               ← produces loadable tarball
Step 4: Layer count check                ← ≤ 3 layers
Step 5: Size budget check                ← ≤ 400 MB
Step 6: Push to Artifact Registry        ← only on master/main
```

### Nightly Pipeline (`cloudbuild-nightly.yaml`)

Runs at 02:00 UTC. Full build (< 4 hours).

```
Step 1: Build ALL targets (//...)
Step 2: VS platform smoke test (QEMU)
Step 3: Size regression check vs baseline
```

### Running CI locally

```bash
# Simulate the PR pipeline
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_PROJECT_ID=$(gcloud config get-value project)

# Or just run the checks manually:
bazel run //:buildifier_check                                    # Step 1
bazel build //dockers/docker-orchagent:docker_orchagent           # Step 2
bazel build //dockers/docker-orchagent:docker_orchagent_tarball   # Step 3
docker load -i $(bazel cquery --output=files //dockers/docker-orchagent:docker_orchagent_tarball)
docker inspect sonic/docker_orchagent:dev | jq '.[0].RootFS.Layers | length'  # Step 4
```

---

## 12. Cross-Compilation

Build for different architectures using `--config`:

```bash
# ARM64 (e.g., NVIDIA BlueField, Marvell)
bazel build //src/sonic-swss-common:swss_common_debs --config=arm64

# ARMv7 (e.g., some older platforms)
bazel build //src/sonic-swss-common:swss_common_debs --config=armhf
```

Cross-compilation is handled by the LLVM toolchain (`toolchains_llvm`
in `MODULE.bazel`) and platform constraints in `platforms/BUILD.bazel`:

```python
# platforms/BUILD.bazel defines:
# //platforms:linux_amd64   (default)
# //platforms:linux_arm64
# //platforms:linux_armhf
```

Debian packages use `select()` to set `CONFIGURED_ARCH`:

```python
arch = select({
    "//platforms:is_amd64": "amd64",
    "//platforms:is_arm64": "arm64",
    "//platforms:is_armhf": "armhf",
})
```

---

## 13. Troubleshooting

### "no such package" or "target not found"

```bash
# Check if submodules are initialized
git submodule status | grep "^-"
# If any show "-", run:
git submodule update --init --recursive
```

### "sandbox_default_allow_network is blocking my build action"

Network access is intentionally blocked in build actions. If a genrule needs
to download something, it's incorrectly designed. Fix: move the download to
a `repository_rule` in `MODULE.bazel`.

### "stripped_layer: FAIL: layer is X MB, exceeds Y MB budget"

The layer is too large. Options:
1. Check if unnecessary packages were added to the apt install list
2. Verify debug symbols are being stripped
3. Check if `--no-install-recommends` is set
4. Audit with: `tar -tzf layer.tar | sort -k3 -rn | head -20`

### "execution_requirements is not a valid attribute for genrule"

`execution_requirements` is only valid on custom Starlark rules, not native
`genrule`. For genrules, use `tags` for scheduling hints.

### Build is slow on first run

First build downloads all external dependencies and builds from scratch.
Subsequent builds use Bazel's incremental cache. For CI, use the GCS
remote cache:

```bash
bazel build --config=ci //...
```

### "PLACEHOLDER" errors in slave_image

The sonic-slave container digests in `rules/bazel/deb/deb.bzl` are
placeholders. Before running actual .deb builds:

```bash
# Get the real digest:
crane digest us-docker.pkg.dev/PROJECT_ID/sonic/sonic-slave-bullseye:latest

# Update in deb.bzl and toolchains/BUILD.bazel
```

---

## 14. Migration Status

### What Bazel builds today

| Component | Status | Targets |
|---|---|---|
| 36 src/ packages (.deb, .whl) | BUILD.bazel written | 97 |
| 26 Docker images (OCI) | BUILD.bazel written | 414 |
| 3 platform images (.bin, .swi) | BUILD.bazel written | 22 |
| Size enforcement rules | Active (41 stripped_layer + 1 filtered_modules) | 42 |
| CI pipelines | cloudbuild.yaml + nightly | — |

### What the Make system still handles

The Make system (`slave.mk` + `rules/*.mk`) remains functional and
authoritative. It is **not deleted** until each Bazel equivalent passes
`debdiff` verification.

### Completing the migration

For each package, the migration is complete when:

1. `bazel build //src/PKG:target` succeeds with `--sandbox_debug`
2. `debdiff make_output.deb bazel_output.deb` shows only timestamp diffs
3. Build is reproducible (two clean builds → identical output)
4. OCI image has ≤ 3 layers and is within size budget
5. Cloud Build passes with ≥ 80% remote cache hit rate on re-run
6. The corresponding `.mk` file is archived (moved to `rules/legacy/`)
