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

## Phase 3 — Dependency Trimming (Planned)

These entries are planned removals, not yet implemented. Each will be
verified and moved to Phase 2 section above once confirmed.

### locales (non-en)
- **Plan**: Replace `locales-all` with `locales` + `LANG=C.UTF-8` only.
  Saves ~200 MB across all images.

### python2.7, python-* packages
- **Plan**: Fully removed in bookworm target (no Python 2 in bookworm).
  Saves ~50 MB per image that had Python 2.

### Kernel module trimming (sonic-broadcom.bin)
- **Plan**: Use per-SKU modules.dep allowlist. Only load modules used by the
  specific hardware platform. Target savings: 20–40 MB.

### frr debug symbols
- **Plan**: Build frr with --disable-doc --disable-grpc, strip debug.
  Current ~60 MB → target ~35 MB.

### man pages, /usr/share/doc
- **Plan**: Already handled by dpkg exclude config in sonic-common-layer
  (01_sonic_excludes). Saves ~30 MB across all images.
