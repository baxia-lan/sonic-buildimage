# Handoff: SONiC Make-to-Bazel Migration

**Date**: 2026-04-12  
**Branch**: `claude`  
**Repo**: `baxia-lan/sonic-buildimage`  
**Last commit**: `0017fd803` — ci: add start.sh debug output  

---

## 1. Project Goal

Migrate SONiC buildimage from GNU Make to Bazel (bzlmod), fully hermetic.  
Reference implementation: https://github.com/thesayyn/sonic-buildimage (Aspect's work).

Read `CLAUDE.md` at repo root before doing any work. It is the execution protocol.

---

## 2. Acceptance Gates

### Gate 1 (current focus): docker-sonic-vs.gz
```
bazel test //acceptance:vs_pytest --sandbox_default_allow_network=false
```
- Build docker-sonic-vs.gz with Bazel
- Load image, boot container, all 40+ services start
- sonic-swss full pytest suite passes (start with `test_port.py`)

### Gate 2: Cloud Build CI with remote cache >= 80% hit rate
### Gate 3: sonic-broadcom.bin (hermetic kernel + platform)
### Gate 4: sonic-alpinevs.img.gz

---

## 3. What Works (verified in CI run 24313803633)

| Component | Status |
|---|---|
| Orchagent chain (swss-common, sairedis, swss, dash-api) | BUILD passes |
| All 8 service Docker images | BUILD passes |
| docker-sonic-vs BUILD + LOAD | Passes — image loads, ~596 MB |
| Kernel build (linux_kernel_debs) | BUILD passes |
| sonic-broadcom.bin | BUILD passes (596 MB) |
| Usrmerge OCI fix | Working — `/bin -> usr/bin` correct |
| start.sh found + executable | Yes |
| HWSKU directory + lanemap.ini | Present |
| supervisord starts | Yes |

---

## 4. Current Blocker: Container Boot Fails

**CI run**: 24313803633  
**Failing step**: "Verify docker-sonic-vs contents"  
**Symptom**: `start.sh` exits with status 1 immediately, supervisor gives up after 4 retries.

### Three root causes identified from `bash -x` trace:

#### 4a. `libbpf.so.1` missing
```
ip: error while loading shared libraries: libbpf.so.1: cannot open shared object file
```
- `ip link show` fails -> empty MAC address -> downstream failures
- **Fix**: Add `@bookworm_libbpf1_1-1.1.2-0-p-deb12u1_amd64//:data` to `common_apt_slim_layer` in `dockers/sonic-common-layer/BUILD.bazel`
- The package is already in `use_repo(apt, ...)` at MODULE.bazel line 274, just not included in the layer

#### 4b. `libpython3.11.so.1.0` missing
```
ls: cannot access '/usr/lib/x86_64-linux-gnu/libpython3.11*': No such file or directory
```
- swsscommon SWIG binding (`_swsscommon.so`) links against this
- A `python_runtime_deps` repo was created via `runtime_deps_repo` (MODULE.bazel line 218), and its layer is in `sonic_common_layer` tars list, BUT the files are NOT appearing in the final container
- **Root cause**: Unknown. The `runtime_deps_repo` rule downloads, extracts, and repacks correctly (verified manually: deb contains `data.tar.xz` with `usr/lib/x86_64-linux-gnu/libpython3.11.so.1.0`, sha256 matches)
- **Recommended fix**: Abandon `runtime_deps_repo` approach. Use `http_file` + `deb_extract_layer_hermetic` instead (proven pattern, used by other images). Or add `libpython3.11` to the rules_distroless apt manifest
- The `libpython3.11` deb URL and sha256 are verified:
  ```
  URL: https://snapshot.debian.org/archive/debian/20260401T000000Z/pool/main/p/python3.11/libpython3.11_3.11.2-6+deb12u6_amd64.deb
  SHA256: 6a824827e991ff23555954a3496a4a49be660dcdd0e7dbb1dc80171782fbd463
  ```

#### 4c. `sonic-cfggen` crashes importing `portconfig.py`
```
Traceback (most recent call last):
  File "/usr/local/lib/python3.11/dist-packages/portconfig.py", line 8, in <module>
```
- Line 8 is: `from swsscommon import swsscommon` — this fails because `libpython3.11.so.1.0` is missing
- Fix 4b and this resolves automatically

### Cascade:
```
libbpf missing -> ip fails -> empty MAC address
libpython3.11 missing -> swsscommon import fails -> sonic-cfggen crashes
                       -> start.sh exits 1 (bash -e)
```

---

## 5. Exact Files to Edit

### Fix 1: Add libbpf1 to common layer
**File**: `dockers/sonic-common-layer/BUILD.bazel`  
**Location**: `slim_apt_layer.srcs` list (line ~68-85)  
**Add**:
```python
"@bookworm_libbpf1_1-1.1.2-0-p-deb12u1_amd64//:data",
```
Also consider adding `@bookworm_libelf1_0.188-2.1_amd64//:data` and `@bookworm_libmnl0_1.0.4-3_amd64//:data` (other iproute2 runtime deps).

### Fix 2: Replace python_runtime_deps with http_file + deb_extract_layer_hermetic

**Option A (recommended)**: In `MODULE.bazel`, add:
```python
_http_file(
    name = "libpython3_11_deb",
    url = "https://snapshot.debian.org/archive/debian/20260401T000000Z/pool/main/p/python3.11/libpython3.11_3.11.2-6+deb12u6_amd64.deb",
    sha256 = "6a824827e991ff23555954a3496a4a49be660dcdd0e7dbb1dc80171782fbd463",
    downloaded_file_path = "libpython3.11.deb",
)
```
Then in `dockers/sonic-common-layer/BUILD.bazel`:
```python
load("//rules/bazel/oci:docker_layer.bzl", "deb_extract_layer_hermetic")

deb_extract_layer_hermetic(
    name = "libpython3_11_layer",
    debs = ["@libpython3_11_deb//file"],
)
```
And change the `sonic_oci_image` tars to use `:libpython3_11_layer` instead of `@python_runtime_deps//:layer`.

**Option B**: Add `libpython3.11` to the rules_distroless apt manifest and reference it as `@bookworm_libpython3.11_...//:data` in the slim_apt_layer.

### Fix 3: Increase bash -x trace output
**File**: `.github/workflows/build-orchagent.yml` line 187  
Change `head -30` to `head -100` to capture full traceback in future runs.

---

## 6. Architecture Overview

### OCI Image Layer Stack (docker-sonic-vs)
```
@debian_bookworm_slim                     (base)
  -> sonic_common_layer                   (dockers/sonic-common-layer/BUILD.bazel)
       layers:
         common_apt_slim_layer            (iproute2, redis, rsyslog, python3, jq, etc.)
         @python_runtime_deps//:layer     (libpython3.11 — BROKEN, needs fix)
         supervisord_skel_layer           (/etc/supervisor/supervisord.conf)
         rsyslog_layer                    (/etc/rsyslog.conf)
  -> docker_sonic_vs                      (platform/vs/BUILD.bazel)
       adds: sonic-config-engine, swss debs, FRR, syncd, device data, start.sh, etc.
```

### Key Bazel Rules
| File | Purpose |
|---|---|
| `rules/bazel/oci/oci.bzl` | `sonic_oci_image` — wraps `oci_image` + `oci_load` |
| `rules/bazel/oci/sonic_docker.bzl` | `slim_apt_layer`, `sonic_docker_image` — slimming + image assembly |
| `rules/bazel/oci/docker_layer.bzl` | `deb_extract_layer_hermetic` — extract .deb to tar without Docker |
| `rules/bazel/deb/runtime_deps_repo.bzl` | `runtime_deps_repo` — repo rule for hermetic .deb download |
| `rules/bazel/deb/frr_repo.bzl` | `frr_deb_repo` — FRR package repo rule |

### Critical Discovery: OCI Usrmerge Conflict
Debian bookworm packages (iproute2, bridge-utils) ship files in `./bin/`, `./sbin/`. When these become OCI tar layers on top of a base image with `/bin -> /usr/bin` symlinks, the directories shadow the symlinks in Docker overlayfs, making `/bin/bash` unreachable.

**Fix applied everywhere**: before tarring, move `./bin/`, `./sbin/`, `./lib/` into `./usr/`. Applied in:
- `rules/bazel/oci/sonic_docker.bzl` (`_SLIM_CMD` step 7)
- `rules/bazel/oci/docker_layer.bzl` (`deb_extract_layer_hermetic`)
- `rules/bazel/deb/runtime_deps_repo.bzl`
- `rules/bazel/deb/frr_repo.bzl`
- `platform/vs/BUILD.bazel` (vs_frr_layer genrule)
- `dockers/docker-snmp/BUILD.bazel`, `dockers/docker-lldp/BUILD.bazel`, `dockers/docker-fpm-frr/BUILD.bazel`

---

## 7. CI Pipeline

**File**: `.github/workflows/build-orchagent.yml`  
**Trigger**: push to `claude` branch  
**Runner**: `ubuntu-latest` (2 vCPU, 7 GB RAM, ~50 GB disk after cleanup)

### Steps (in order):
1. Checkout + submodule align to 202405 release commits
2. Copy BUILD.bazel/MODULE.bazel from forked submodule repos
3. Install Bazelisk
4. (optional) Setup GCP remote cache if `GCP_SA_KEY` secret exists
5. Free disk space + build team kernel module
6. Build orchagent chain
7. Build all service images
8. Build + load docker-sonic-vs
9. **Verify docker-sonic-vs contents** <-- currently fails here
10. Run pytest test_port.py
11. Build kernel + sonic-broadcom.bin (if: always)
12. Verify outputs + upload artifacts

### Submodule Repos (forked with BUILD.bazel)
Each submodule has a fork on `baxia-lan/` GitHub with a `claude` branch containing `BUILD.bazel`:
- `sonic-swss-common` (pinned: 36f40a1bae)
- `sonic-sairedis` (pinned: edd144b643)
- `sonic-swss` (pinned: 6785d6620)
- `sonic-dash-api` (pinned: 3f6709001)
- `sonic-linux-kernel` (pinned: feaf559f38)
- `sonic-stp`, `sonic-gnmi`, `sonic-platform-daemons`, `sonic-utilities`, `sonic-host-services`

BUILD.bazel files are downloaded from the fork at CI time (step 2).

---

## 8. Local Build Setup

The user explicitly wants local Docker builds, not CI-only. The approach:

```bash
# 1. Start build container (privileged, Docker socket mounted)
docker run -d --name sonic-build --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $PWD:/workspace -w /workspace \
  ubuntu:24.04 sleep infinity

# 2. Install deps inside container
docker exec sonic-build bash -c '
  apt-get update && apt-get install -y curl git python3 binutils xz-utils zstd
  curl -Lo /usr/local/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64
  chmod +x /usr/local/bin/bazel
'

# 3. Build VS image
docker exec sonic-build bazel build //platform/vs:docker_sonic_vs_tarball \
  --spawn_strategy=local --jobs=4

# 4. Load and test
docker exec sonic-build bash bazel-bin/platform/vs/docker_sonic_vs_tarball.sh
docker tag sonic/docker_sonic_vs:latest docker-sonic-vs:latest
docker run --rm --privileged docker-sonic-vs:latest bash -x /usr/bin/start.sh 2>&1 | head -100
```

**Note**: `binutils` (provides `ar`) MUST be installed or FRR repo fetch fails with empty BUILD.bazel.

---

## 9. start.sh Dependencies (what the container needs)

The script `platform/vs/docker-sonic-vs/start.sh` (shebang: `#!/bin/bash -e`) requires:

**Critical binaries**: `bash`, `ip`, `sonic-cfggen`, `supervisorctl`, `redis-server`, `redis-cli`, `grep`, `awk`, `sed`, `jq`, `pushd`/`popd`

**Critical files**:
- `/usr/share/sonic/device/x86_64-kvm_x86_64-r0/` — platform dir
- `/usr/share/sonic/device/x86_64-kvm_x86_64-r0/Force10-S6000/` — HWSKU dir
- `/usr/share/sonic/device/.../lanemap.ini`, `port_config.ini`, `sai.profile`
- `/usr/share/sonic/templates/init_cfg.json.j2`, `copp_cfg.j2`
- `/etc/default/sonic-db/database_config.json`
- `/etc/sonic/sonic_version.yml`

**Critical shared libs**: `libbpf.so.1` (for `ip`), `libpython3.11.so.1.0` (for swsscommon SWIG)

**Environment vars** (set in OCI image): `PLATFORM=x86_64-kvm_x86_64-r0`, `HWSKU=Force10-S6000`

**Boot sequence**: symlinks platform/hwsku -> runs sonic-cfggen -> starts redis -> loads config_db -> starts all 30+ supervisord programs

---

## 10. Remaining Work (priority order)

### Immediate (unblock Gate 1 container boot)
1. [x] Add `libbpf1` (+ libelf1, libmnl0) to `common_apt_slim_layer` srcs — DONE
2. [x] Fix libpython3.11 deployment — switched to `http_file` + `deb_extract_layer_hermetic` — DONE
3. [ ] Increase `bash -x` trace from `head -30` to `head -100` in CI
4. [ ] Commit, push, verify container boots (start.sh exits 0, services reach RUNNING)

### Next (Gate 1 pytest)
5. [ ] After boot works, run `pytest test_port.py` — expect new failures (missing Python packages, network config, etc.)
6. [ ] Add any missing Python packages to the VS image layers
7. [ ] Debug sonic-cfggen template rendering issues
8. [ ] Verify all 17 services that conftest.py checks reach RUNNING state

### Gate 1 completion
9. [ ] `test_port.py` passes end-to-end
10. [ ] debdiff: compare Make-built vs Bazel-built .deb outputs
11. [ ] Two-build reproducibility: sha256 identical outputs

### Gate 2
12. [ ] Set up `GCP_SA_KEY` secret for remote cache (user action)
13. [ ] Verify cache hit rate >= 80% on second build

### Gate 3-4
14. [ ] sonic-broadcom.bin hermetic build verification
15. [ ] sonic-alpinevs.img.gz Bazel target

---

## 11. Key Gotchas

1. **Never run `bazel mod tidy`** on this repo — it strips individual package repos from `use_repo(apt, ...)`, breaking all BUILD files. If it happens, `git checkout HEAD -- MODULE.bazel`.

2. **macOS builds**: Set `COPYFILE_DISABLE=1` before tar commands. Use `gtar` (GNU tar) from Homebrew for `--sort`/`--mtime` flags. Already handled in all rules.

3. **`ar` not in Ubuntu minimal images**: The `runtime_deps_repo` and `frr_deb_repo` rules use `ar x` during fetch. Make sure `binutils` is installed.

4. **Submodule BUILD.bazel sync**: CI downloads BUILD.bazel files from fork branches at runtime. If you change a submodule's BUILD.bazel, push to the `claude` branch of the corresponding `baxia-lan/<submodule>` fork.

5. **`--spawn_strategy=local`**: Required on CI because the Bazel sandbox can't run Docker commands. All build actions are still hermetic (no network), but filesystem isolation is relaxed.

6. **Hermeticity rules**: `--sandbox_default_allow_network=false` in `.bazelrc`. Network only in `repository_rule`s. All downloads sha256-pinned. `SOURCE_DATE_EPOCH=0` on all packaging.

---

## 12. File Index

| Path | What it does |
|---|---|
| `MODULE.bazel` | Bzlmod deps: rules_oci, rules_distroless apt packages, FRR, runtime_deps |
| `dockers/sonic-common-layer/BUILD.bazel` | Shared base for all SONiC containers |
| `platform/vs/BUILD.bazel` | docker-sonic-vs assembly (OCI layers, device data, start.sh) |
| `rules/bazel/oci/oci.bzl` | `sonic_oci_image` wrapper |
| `rules/bazel/oci/sonic_docker.bzl` | `slim_apt_layer` + `_SLIM_CMD` |
| `rules/bazel/oci/docker_layer.bzl` | `deb_extract_layer_hermetic` |
| `rules/bazel/deb/runtime_deps_repo.bzl` | Hermetic deb download repo rule |
| `rules/bazel/deb/frr_repo.bzl` | FRR package repo rule |
| `.github/workflows/build-orchagent.yml` | CI pipeline (all steps) |
| `platform/vs/docker-sonic-vs/start.sh` | Container boot script |
| `src/sonic-config-engine/portconfig.py` | Crashes at line 8 (swsscommon import) |
| `.bazelrc` | Bazel config (hermeticity flags) |
| `CLAUDE.md` | Execution protocol (READ THIS FIRST) |

---

## 13. CI Run History

| Run | Commit | Failure | Root Cause |
|---|---|---|---|
| 24313803633 | 0017fd803 | start.sh exit 1 | libbpf.so.1 + libpython3.11.so missing |
| 24312119913 | eee8e9530 | start.sh exit 127 | usrmerge: ./bin/ shadows /bin -> /usr/bin |
| 24300869138 | — | start.sh exit 127 | Same usrmerge issue |
| 24300674107 | — | dwarf.h missing | gendwarfksyms needs libdw-dev |
| 24299600639 | — | modprobe team fails | /lib/modules not enough |
| 24297170582 | — | supervisord crash | supervisord_env.conf + no /lib/modules |
