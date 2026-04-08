# SONiC Buildimage — Bazel Build System

> Make → Bazel (bzlmod) migration for [sonic-buildimage](https://github.com/sonic-net/sonic-buildimage).
> Branch: `claude` on `baxia-lan/sonic-buildimage`.

## Status

| Component | Status | Notes |
|---|---|---|
| Bazel infrastructure | ✅ Working | 8.5.1 + bzlmod, 202 BUILD.bazel |
| Hermetic Debian packages | ✅ Working | 190 packages via rules_distroless |
| C++ toolchain | ✅ Working | LLVM/Clang 18 + Bookworm sysroot |
| .deb compilation | ✅ Working | 29 real packages from source |
| Docker service images | �� Working | 9 hermetic + 1 with orchagent |
| sonic-broadcom.bin | ✅ Working (local) | Stub kernel, real orchagent |
| Linux kernel | ⏳ CI building | cpupower.install fix in progress |
| Size reduction | ✅ 75% on base layer | 160 MB → 39 MB |

## Architecture

```
sonic-buildimage/
├── MODULE.bazel                 # Root module — all external deps
├── .bazelrc                     # Hermeticity flags
├─��� .bazelversion                # 8.5.1
│
├── apt/
│   └── bookworm.yaml            # 190 Debian packages manifest
│
├── toolchains/
│   ├── cc/
│   │   └── sysroot.bzl          # Hermetic sysroot from .deb packages
│   └── gcc/
│       └── gcc.bzl              # GCC 12.5 fetch (backup)
│
├── rules/bazel/
│   ├��─ deb/deb.bzl              # deb_package_set() — .deb from source
│   ├── oci/
│   │   ├── oci.bzl              # sonic_oci_image()
│   │   ├── sonic_docker.bzl     # slim_apt_layer() — size reduction
│   │   ├── docker_layer.bzl     # apt_install_layer() (transitional)
│   │   └── hermetic_layer.bzl   # deb_layer() from rules_distroless
│   ├── onie/
│   │   ├��─ onie.bzl             # onie_image() — .bin assembly
│   │   ├── onie_installer.bzl   # ONIE sharch format
│   │   ├── aboot.bzl            # Arista .swi format
│   │   ├── rootfs.bzl           # Rootfs with OCI layer dedup
│   │   └── module_filter.bzl    # Kernel module allowlist
│   ├── wheel/wheel.bzl          # sonic_wheel()
│   ├── j2/j2.bzl                # j2_render() build-time Jinja2
│   ├── test/deb_test.bzl        # Component test rule
│   └─�� verify.bzl               # hermetic_test(), size_test()
│
├── src/*/BUILD.bazel             # 36 source package builds
├── dockers/*/BUILD.bazel         # 55 Docker image builds
├── platform/*/BUILD.bazel        # 24 platform builds
└── files/*/BUILD.bazel           # 18 support file exports
```

## How It Works

### Layer 1: Dependency Resolution (fetch time, hermetic)

All Debian packages are resolved **before** the build starts, from a pinned
`snapshot.debian.org` mirror:

```
MODULE.bazel
  └── rules_distroless apt.install()
      └── apt/bookworm.yaml (190 packages)
          └── @bookworm_redis-server_5-7.0.15_amd64//:data
          └── @bookworm_iproute2_6.1.0-3_amd64//:data
          └── ... (190 packages, all pinned by version + sha256)
```

No `apt-get` runs during the build. No network access in build actions.

### Layer 2: C/C++ Compilation

Two modes:

**Hermetic (for CI on Linux):**
```
toolchains_llvm (Clang 18)
  + @bookworm_sysroot (libc6-dev, libgcc-12-dev, libstdc++-12-dev)
  → native cc_library/cc_binary compilation in Bazel sandbox
```

**Docker genrule (for macOS and dpkg-buildpackage):**
```
deb_package_set()
  → docker run --platform linux/amd64 debian:bookworm-slim
  → apt-get install build-deps
  → dpkg -i /deps/*.deb (previously-built Bazel outputs)
  → dpkg-buildpackage -b -us -uc
  → real .deb output
```

### Layer 3: Docker Image Assembly

**Hermetic images** (no Docker daemon needed):
```
slim_apt_layer()                    # Merge @bookworm packages, strip ELF,
  → remove man/doc/locale/pycache  # remove docs → 39 MB layer
  → sonic_oci_image()              # Compose with distroless base
```

**Images with compiled .debs:**
```
deb_extract_layer()                 # Extract .deb into layer tar
  + slim_apt_layer()               # Runtime apt packages
  + pkg_tar()                      # Config/scripts
  → sonic_oci_image()
```

### Layer 4: ONIE Image Assembly

```
sonic_rootfs_image()               # Bundle all service Docker images
  + kernel (vmlinuz)               # Linux kernel
  + filtered_modules()             # Allowlist-based module filtering
  → onie_image()                   # Self-extracting .bin (sharch format)
```

## How to Build

### Prerequisites

- Bazelisk: `brew install bazelisk` (reads `.bazelversion` → downloads Bazel 8.5.1)
- Docker Desktop (for .deb compilation on macOS)
- Git submodules: `git submodule update --init --recursive`

### Align submodules to 202405 release

```bash
cd src/sonic-swss-common && git checkout 36f40a1bae && cd ../..
cd src/sonic-sairedis && git checkout edd144b643 && cd ../..
cd src/sonic-sairedis/SAI && git checkout 408d75b610 && cd ../../..
cd src/sonic-swss && git checkout 6785d66208 && cd ../..
cd src/sonic-dash-api && git checkout 3f6709001e && cd ../..
cd src/sonic-linux-kernel && git checkout feaf559f38 && cd ../..
```

### Build hermetic Docker images (no Docker needed, seconds)

```bash
bazel build //dockers/docker-database:docker_database \
  --strategy=CopyToDirectory=local
```

### Build .deb packages from source (needs Docker)

```bash
bazel build //src/sonic-swss-common:swss_common_debs \
  --spawn_strategy=local --jobs=1
```

### Build sonic-broadcom.bin (local, stub kernel)

```bash
bazel build //platform/broadcom:sonic_broadcom_local \
  --spawn_strategy=local --strategy=CopyToDirectory=local --jobs=1
```

### Build sonic-broadcom.bin (CI, real kernel)

```bash
bazel build //platform/broadcom:sonic_broadcom_bin \
  --spawn_strategy=local --jobs=4
```

### Build everything that's hermetic

```bash
bazel build //dockers/... --strategy=CopyToDirectory=local
```

## Package Dependency Chain

```
libnl3 (23 .debs, SONiC-patched from Debian pool)
  │
  └→ sonic-swss-common (7 .debs, 386 KB libswsscommon)
      │
      ���→ sonic-sairedis (11 .debs, SAI metadata + libsaivs)
      │
      ├→ sonic-dash-api (2 .debs, protobuf DASH API)
      │
      ├→ sonic-stp (2 .debs)
      │
      └→ sonic-swss (2 .debs, 3.0 MB, orchagent 7.3 MB binary)
          │
          └→ docker-orchagent (OCI image)
              │
              └→ sonic-broadcom.bin (ONIE installer)
```

## Size Reduction

| Optimization | Before | After | Savings |
|---|---|---|---|
| Base image (distroless vs debian) | 200 MB | 20 MB | 180 MB |
| slim_apt_layer (strip+locale+doc) | 160 MB | 39 MB | 121 MB (75%) |
| No build-essential at runtime | 130 MB | 0 MB | 130 MB |
| No apt/pip at runtime | 30 MB | 0 MB | 30 MB |
| OCI layer dedup (shared base) | 15×200 MB | 1×39 MB | ~2.7 GB |
| Kernel module allowlist | ~400 modules | ~65 modules | 20-40 MB |

**Target: sonic-broadcom.bin < 400 MB** (Make system produces ~1 GB)

## Alignment with Aspect Build

This work is aligned with [Aspect Build's sonic-build-infra](https://github.com/thesayyn/sonic-build-infra):

| Feature | Aspect | This repo | Status |
|---|---|---|---|
| rules_distroless | ✅ | ✅ | Same approach |
| Hermetic LLVM toolchain | ✅ | ✅ | toolchains_llvm 1.7.0 |
| debian_sysroot_repo | ✅ | ✅ | Adopted |
| slim_apt_layer | — | ✅ | From sonic-bazel |
| Real .deb compilation | PR open | ✅ 29 packages | Working |
| Docker image assembly | — | ✅ 9+ images | Working |
| ONIE .bin generation | — | ✅ | Working |

## File Index

| File | Purpose |
|---|---|
| `MODULE.bazel` | Root module: all bazel_dep, toolchains, apt packages |
| `.bazelrc` | Hermeticity flags, CI/RBE configs |
| `.bazelversion` | Bazel 8.5.1 |
| `apt/bookworm.yaml` | Debian package manifest (190 packages) |
| `toolchains/cc/sysroot.bzl` | Hermetic sysroot from .deb extraction |
| `rules/bazel/deb/deb.bzl` | deb_package_set() for .deb compilation |
| `rules/bazel/oci/sonic_docker.bzl` | slim_apt_layer() for size reduction |
| `rules/bazel/oci/oci.bzl` | sonic_oci_image() for OCI assembly |
| `rules/bazel/onie/rootfs.bzl` | Rootfs with OCI layer dedup |
| `rules/bazel/onie/onie.bzl` | onie_image() for .bin assembly |
| `demo.sh` | Live demo script |
| `docs/BAZEL_GAPS.md` | Make vs Bazel gap analysis |
| `docs/BUILD_SYSTEM.md` | Full build system documentation |
| `docs/DEMO_TALKING_POINTS.md` | Presentation talking points |

## Known Issues

1. **Kernel**: Builds on native amd64 CI only. `linux-cpupower.install` fix in progress.
2. **macOS cross-compile**: LLVM sysroot linking fails on macOS (use Docker genrules instead).
3. **Missing services**: FRR, SNMP, LLDP, gNMI images not yet building.
4. **Broadcom SAI**: Proprietary SDK not included.
5. **Tests**: deb_test rule exists but not wired for all packages.
