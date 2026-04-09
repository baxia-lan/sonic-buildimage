# Migration Progress

Last updated: 2026-04-09

## Done

### Infrastructure
- [x] Bazel 8.5.1 + bzlmod (MODULE.bazel)
- [x] rules_distroless 0.3.8 — 190 Debian packages from snapshot.debian.org
- [x] toolchains_llvm 1.7.0 — Hermetic LLVM/Clang 18
- [x] debian_sysroot_repo — Bookworm sysroot from 5 .deb packages
- [x] slim_apt_layer — ELF strip + locale/man/doc removal
- [x] 217+ BUILD.bazel files (88 submodules + 54 dockers + platform + rules)
- [x] MODULE.bazel.lock committed for reproducible apt package resolution
- [x] Hermetic sysroot with 30+ Bookworm dev packages

### .deb Packages (29 from source)
- [x] libnl3 (23 debs, SONiC-patched, dget from Debian pool)
- [x] sonic-swss-common (7 debs, 386 KB libswsscommon)
- [x] sonic-sairedis (11 debs, SAI metadata + libsaivs)
- [x] sonic-dash-api (2 debs, protobuf DASH API)
- [x] sonic-stp (2 debs)
- [x] sonic-swss (2 debs, 3.0 MB, orchagent 7.3 MB)

### Docker Images (15 with BUILD.bazel)
- [x] sonic-common-layer (hermetic, 39 MB)
- [x] docker-database (hermetic)
- [x] docker-teamd (hermetic)
- [x] docker-nat (hermetic)
- [x] docker-sflow (hermetic)
- [x] docker-stp (hermetic)
- [x] docker-iccpd (hermetic)
- [x] docker-router-advertiser (hermetic)
- [x] docker-basic_router (hermetic)
- [x] docker-dhcp-relay (hermetic)
- [x] docker-eventd (hermetic)
- [x] docker-platform-monitor (hermetic)
- [x] docker-sysmgr (hermetic)
- [x] docker-sonic-mgmt-framework (hermetic)
- [x] docker-orchagent (Docker genrule, real binary)

### docker-sonic-vs (OCI image)
- [x] Hermetic oci_image() with 7 layers (5 hermetic, 2 Docker-based)
- [x] slim_apt_layer for runtime packages (rules_distroless)
- [x] deb_extract_layer for Bazel-built SONiC .debs
- [x] FRR + supervisor layer via apt_install_layer
- [x] sonic-cfggen + Python packages layer
- [x] Device data (lanemap.ini, port_config.ini, sai.profile)
- [x] syncd-vs produced with -Psyncd,vs build profiles
- [ ] Boot test on native amd64 Linux
- [ ] sonic-swss pytest passing

### ONIE Image
- [x] sonic-broadcom.bin local build (stub kernel + 9 services)
- [x] ONIE sharch self-extracting format
- [x] Rootfs with OCI layer deduplication
- [x] Size budget framework (slim_apt_layer, filtered_modules)

### CI/CD
- [x] GitHub Actions workflow
- [x] GCS remote cache config (.bazelrc)
- [x] BuildBuddy config (.bazelrc)

### Documentation
- [x] docs/README_BAZEL.md — Architecture + how to build
- [x] docs/BUILD_SYSTEM.md — Full build system guide
- [x] docs/BAZEL_GAPS.md �� Make vs Bazel gap analysis
- [x] docs/DEMO_TALKING_POINTS.md — Presentation materials
- [x] demo.sh — Live demo script

## In Progress

### Kernel
- [x] SOURCE_DATE_EPOCH empty string fix (dpkg-deb timestamp)
- [x] cpupower.install background watcher fix (pushed to fork)
- [ ] CI kernel build passing (watcher fix in pipeline, waiting)
- [ ] sonic-broadcom.bin with real kernel

### More .deb Packages
- [ ] FRR (autotools, complex)
- [ ] snmpd (dget from Debian pool, like libnl3)
- [ ] sonic-gnmi (Go + deb)
- [ ] sonic-mgmt-common
- [ ] gobgp (Go)
- [ ] lldpd

### More Docker Images
- [ ] docker-fpm-frr (needs FRR .deb)
- [ ] docker-snmp (needs snmpd .deb)
- [ ] docker-lldp (pip wheel issue)
- [ ] docker-sonic-gnmi (needs mgmt-common)
- [ ] docker-sonic-telemetry (chains on gnmi)
- [ ] docker-macsec (needs wpasupplicant)
- [ ] docker-mux (needs linkmgrd)
- [ ] docker-syncd-* (vendor SAI)

### Python Wheels
- [ ] sonic-utilities
- [ ] sonic-host-services
- [ ] sonic-py-common
- [ ] sonic-config-engine
- [ ] sonic-yang-models
- [ ] sonic-yang-mgmt
- [ ] sonic-platform-common

### docker-sonic-vs for pytest (Ultimate Verification Target)
- [ ] Build FRR .deb (or use upstream Debian FRR)
- [ ] Build sonic-config-engine (provides sonic-cfggen)
- [ ] Build Python wheels (sonic-utilities, sonic-py-common, sonic-yang-models)
- [ ] Assemble docker-sonic-vs with all 40+ services
- [ ] docker-sonic-vs passes `pytest test_port.py` from sonic-swss/tests
- [ ] docker-sonic-vs passes full sonic-swss pytest suite

## Not Started

- [ ] debdiff verification (Make vs Bazel output comparison)
- [ ] Reproducibility verification (two builds → identical sha256)
- [ ] Remote cache/RBE testing (needs GCP credentials)
- [ ] Upstream PRs to sonic-net
- [ ] Broadcom SAI platform modules (proprietary)
- [ ] Full size verification (sonic-broadcom.bin < 400 MB)
