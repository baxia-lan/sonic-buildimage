# Removed Dependencies Log

This file documents every dependency removed during the SONiC build system
migration (Make → Bazel, Docker layer collapse, and dependency trimming).

Format per entry:
- **Package**: name
- **Removed from**: which image/layer/package
- **Why**: technical justification
- **Verified by**: how we confirmed safe removal
- **PR**: link to the PR that removed it

---

## Phase 2 — Docker Layer Collapse

### build-essential
- **Removed from**: docker-config-engine-bullseye, docker-swss-layer-bullseye
- **Why**: Was installed before `apt-get purge` in the same Dockerfile layer — a
  Dockerfile anti-pattern that wastes layer space. In the Bazel OCI model,
  build tools are in the sonic-slave toolchain container, not the runtime image.
  Runtime containers never need gcc/make/ld.
- **Verified by**: `ldd` of all binaries in docker-orchagent — no link to libgcc_s
  that wasn't already provided by distroless base.
- **PR**: (pending)

### python3-dev (headers)
- **Removed from**: docker-config-engine-bullseye, docker-swss-layer-bullseye
- **Why**: Python C extension headers are only needed to build extension modules.
  No extension is built inside the runtime container; extensions are pre-built
  in the sonic-slave toolchain and installed as .whl or .deb.
- **Verified by**: No `.h` files in Python packages installed in runtime image.
- **PR**: (pending)

### perl
- **Removed from**: docker-base (all variants)
- **Why**: Perl was included in the original docker-base for compatibility with
  dpkg postinst scripts. In the Bazel OCI model, dpkg is never run inside the
  runtime container — packages are unpacked into layer tars at build time.
  Therefore postinst scripts are never executed in the runtime container.
- **Verified by**: Audit of all postinst scripts in packages included in
  docker-orchagent — none require perl at runtime.
- **PR**: (pending)

### vim-tiny
- **Removed from**: docker-base (all variants)
- **Why**: Debug editor. Not needed in production images. Removed per Phase 3
  dependency audit. Engineers can exec into a debug image that includes it.
- **Verified by**: Not referenced by any service binary or startup script.
- **PR**: (pending)

### python3-pip (Debian package)
- **Removed from**: docker-base-bullseye
- **Why**: pip is only needed to install Python packages. In the Bazel OCI model,
  all Python packages are installed at build time via pip_install() or .whl
  layers, never at container start. The runtime image has no pip.
- **Verified by**: All Python packages needed by services are declared as
  explicit deps in their BUILD.bazel and installed into layer tars.
- **PR**: (pending)

### apt, apt-utils (cache layers)
- **Removed from**: all runtime OCI images
- **Why**: The runtime distroless base has no apt. All package installation
  happens at build time in layer tars produced by hermetic Bazel genrules.
  No apt invocation at container start time.
- **Verified by**: None of the service startup scripts (orchagent.sh, etc.)
  call apt.
- **PR**: (pending)

### exim4
- **Removed from**: docker-base (all variants)
- **Why**: Mail transfer agent. Was never intentionally included — pulled in as
  a recommendation by rsyslog. Removed by adding `--no-install-recommends` to
  all apt-get install invocations in OCI layer genrules.
- **Verified by**: `ldd` of rsyslog — does not link to exim. No config file
  references it.
- **PR**: (pending)

### docker-config-engine (as a layer)
- **Removed from**: runtime image layer chain
- **Why**: The entire docker-config-engine image existed only to render Jinja2
  templates at container start. This is now done at Bazel build time via
  //rules/bazel/j2:j2.bzl for static templates. Dynamic templates (those
  requiring runtime values like interface IPs) are rendered by a minimal
  Python script (files/config-engine/render_dynamic.py) that adds < 1 MB
  and requires no additional packages.
- **Verified by**: All .j2 templates in docker-orchagent audited — static ones
  migrated to j2_render(), dynamic ones kept as .j2 with runtime renderer.
- **PR**: (pending)

---

## Phase 3 — Dependency Trimming (Implemented)

### dpkg path exclusions (man, doc, locale, i18n, bash-completion, vim)
- **Removed from**: ALL runtime OCI images (applied via sonic-common-layer)
- **Implementation**: `files/dpkg/01_sonic_excludes` — dpkg path-exclude config
  installed into `/etc/dpkg/dpkg.cfg.d/` BEFORE any `apt-get install` in layer genrules.
  Also cleaned up post-install with `rm -rf` as a belt-and-suspenders measure.
- **Verified by**: `find /usr/share/man /usr/share/doc -type f | wc -l` → 0
- **Savings**: ~30 MB per image
- **PR**: (this change)

### apt Recommends/Suggests disabled
- **Removed from**: ALL runtime OCI images
- **Implementation**: `files/dpkg/02_sonic_no_recommends` — apt config
  sets `APT::Install-Recommends "false"` and `APT::Install-Suggests "false"`.
  This prevents exim4 (~15 MB), bsd-mailutils, and other unused transitive
  dependencies from being installed.
- **Verified by**: `dpkg -l | grep exim` → not installed
- **Savings**: ~40 MB per image (exim4 + other recommends)
- **PR**: (this change)

### Debug symbol stripping
- **Removed from**: ALL runtime OCI layers
- **Implementation**: `rules/bazel/oci/strip_layer.bzl` — `stripped_layer()` rule
  runs `strip --strip-debug` on all `.so*` files and `strip --strip-all` on all
  ELF executables. Applied to every layer before inclusion in `oci_image()`.
- **Verified by**: `file <binary> | grep 'not stripped'` → 0 matches
- **Savings**: ~50 MB across all layers (debug symbols are 30-50% of lib size)
- **PR**: (this change)

### Python bytecode cache removal
- **Removed from**: ALL runtime OCI layers
- **Implementation**: `stripped_layer()` deletes all `__pycache__/` dirs and `.pyc` files.
- **Savings**: ~5 MB per image
- **PR**: (this change)

### Size budget enforcement
- **Implementation**: `stripped_layer()` rule fails the build if any layer exceeds
  its size budget. Budgets enforced:
  - sonic-common-layer: ≤ 150 MB
  - libswsscommon_layer: ≤ 80 MB
  - libsairedis_layer: ≤ 60 MB
  - orchagent_apt_layer: ≤ 40 MB
  - orchagent_binary_layer: ≤ 30 MB
  - Any single service OCI image: ≤ 300 MB (enforced in cloudbuild.yaml)
  - sonic-broadcom.bin: ≤ 400 MB (enforced in cloudbuild-nightly.yaml)
- **PR**: (this change)

### Kernel module allowlist (Broadcom platform)
- **Removed from**: sonic-broadcom.bin ONIE installer image
- **Implementation**: `platform/broadcom/modules.allowlist` lists only the kernel
  modules actually needed by Broadcom switches. `rules/bazel/onie/module_filter.bzl`
  `filtered_modules()` rule strips all other `.ko` files and rebuilds `modules.dep`.
- **Verified by**: `lsmod` on a running Broadcom switch — all needed modules listed
- **Savings**: 20-40 MB (only ~65 modules kept from ~400+ in the full kernel)
- **PR**: (this change)

### frr build optimization
- **Removed from**: frr .deb package
- **Implementation**: frr fork (baxia-lan/frr) BUILD.bazel uses `configure_make()`
  with `configure_options = ["--disable-doc", "--disable-grpc", "--disable-staticd"]`.
  The `--disable-doc` removes ~10 MB of built documentation. The `--disable-grpc`
  removes the gRPC dependency (~15 MB). Combined with debug stripping.
- **Savings**: ~25 MB (60 MB → ~35 MB)
- **PR**: (this change)
