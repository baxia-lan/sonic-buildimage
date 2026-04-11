# Native Build Migration Plan

## Goal
Eliminate Docker genrules (deb_package_set, apt_install_layer) by migrating to
native cc_library builds. This achieves full hermeticity per CLAUDE.md.

## Current State (Docker genrule approach)
```
Source (submodule) → Docker container (apt-get + dpkg-buildpackage) → .deb → deb_extract_layer → OCI layer
```
Problems: network in build actions, no-sandbox required, non-hermetic

## Target State (Aspect native approach)
```
Source (submodule) → cc_library/cc_binary (hermetic LLVM + sysroot) → tar(mtree) → OCI layer
```
Benefits: zero Docker, zero network, fully hermetic, faster builds

## Migration Phases

### Phase 1: Current (working, not hermetic) ✅
- Docker genrules with builder image fallback
- FRR runtime deps via repository_rule (hermetic)
- snapshot.debian.org pinning for determinism

### Phase 2: Verify native cc_library on CI
- Build `//src/sonic-swss-common:swsscommon` with LLVM toolchain on CI
- Verify LLVM 18 + bookworm sysroot produces correct amd64 binaries
- Add CI step: `bazel build //src/sonic-swss-common:libswsscommon_so`

### Phase 3: Native packaging with tar+mtree
- Use `sonic_binary_layer` rule (rules/bazel/pkg/sonic_pkg.bzl)
- Package native binaries into OCI layer tars
- Verify file paths match deb_extract_layer output

### Phase 4: Replace deb_extract_layer
- For swss-common: use native `libswsscommon_so` + `sonic_db_cli`
- For sonic-swss: need native cc_binary for orchagent et al. (big effort)
- For sonic-sairedis: need native syncd build

### Phase 5: Remove Docker genrules
- Delete deb_package_set, apt_install_layer
- Remove no-sandbox tags
- All build actions hermetic (sandboxed, no network)

## Prerequisites
- Upgrade rules_distroless 0.3.8 → 0.6.2 (for cc_deb_library)
- Verify LLVM hermetic toolchain works on CI
- Port all cc_binary deps from sonic-swss/sonic-sairedis

## Reference
- Aspect pattern: thesayyn/sonic-swss-common/BUILD (242 lines)
- Aspect pattern: thesayyn/sonic-swss/orchagent/BUILD
- Our sonic_binary_layer: rules/bazel/pkg/sonic_pkg.bzl
