# Hermetic docker-sonic-vs: Migration Plan

## Goal
Build docker-sonic-vs.gz with `bazel build` — fully hermetic (no Docker in build,
no dpkg-buildpackage, no apt-get at build time). Image must pass sonic-swss pytest.

## Architecture (following Aspect/thesayyn pattern)

```
                    rules_distroless (snapshot.debian.org)
                              │
                    ┌─────────┴─────────┐
                    │   apt packages    │  (libhiredis, libboost, redis-server, FRR, ...)
                    └─────────┬─────────┘
                              │
     ┌────────────────────────┼────────────────────────┐
     │                        │                        │
 cc_library              cc_library              cc_library
 swss-common             sairedis                  swss
 (native build)       (native build)          (native build)
     │                    │    │                    │
     │                    │  vslib                  │
     │                    │  syncd                  │
     └────────┬───────────┴────────────────────────┘
              │
        tar() + mtree     (file placement: /usr/bin/orchagent, /usr/lib/...)
              │
        flatten()         (dedup across layers)
              │
        oci_image()       (rules_oci, no Dockerfile)
              │
    docker-sonic-vs.tar.gz
```

## Phase 1: Add dev libraries to apt manifest (Day 1)

Add to `apt/bookworm.yaml`:
- libhiredis-dev (for swss-common, swss)
- libboost-serialization-dev (for swss-common)
- libzmq3-dev (for swss-common)
- libnl-3-dev, libnl-genl-3-dev, libnl-route-3-dev (for swss-common)
- libgtest-dev, libgmock-dev (for tests)
- nlohmann-json3-dev (for swss-common)
- libyang2-dev (for swss-common)
- uuid-dev (for swss-common)

These packages are consumed at fetch time from snapshot.debian.org.
No network access during build.

## Phase 2: Native cc_library for swss-common (Day 1-2)

Following Aspect's pattern:
```python
cc_library(
    name = "common",
    srcs = glob(["common/*.cpp"]),
    hdrs = glob(["common/*.h"]),
    deps = [
        "@bookworm//libhiredis-dev:libhiredis",
        "@bookworm//libboost-serialization-dev:libboost_serialization",
        "@bookworm//libnl-3-dev:libnl-3",
        "@bookworm//libnl-genl-3-dev:libnl-genl-3",
        "@bookworm//libnl-route-3-dev:libnl-route-3",
        "@bookworm//libzmq3-dev:libzmq",
        "@bookworm//libyang2-dev:libyang",
        "@bookworm//nlohmann-json3-dev:nlohmann-json",
    ],
)
```

Key outputs:
- `libswsscommon.so` — via `cc_binary(linkshared=True)`
- `sonic-db-cli` — via `cc_binary`
- Python bindings — via SWIG rules

## Phase 3: Native cc_library for sairedis (Day 2-3)

- libsairedis, libsaimetadata, libsaivs
- syncd-vs binary
- SAI headers from submodule

## Phase 4: Native cc_library for swss (Day 3-4)

- orchagent, portsyncd, neighsyncd, etc.
- All manager daemons (vlanmgrd, intfmgrd, portmgrd, etc.)

## Phase 5: Hermetic docker-sonic-vs assembly (Day 4-5)

```python
oci_image(
    name = "docker_sonic_vs",
    base = "//dockers/docker-config-engine:image",
    tars = [
        ":swss_layer",      # orchagent, managers, etc.
        ":sairedis_layer",   # syncd-vs, libsaivs
        ":frr_layer",        # FRR from apt
        ":redis_layer",      # redis-server from apt
        ":config_layer",     # supervisord.conf, start.sh, etc.
    ],
    env = {
        "PLATFORM": "x86_64-kvm_x86_64-r0",
        "HWSKU": "Force10-S6000",
    },
    entrypoint = ["/usr/bin/supervisord"],
)
```

## Phase 6: pytest verification (Day 5)

```bash
bazel build //platform/vs:docker_sonic_vs
docker load < bazel-bin/platform/vs/docker_sonic_vs/tarball.tar
docker tag ... docker-sonic-vs:latest
cd src/sonic-swss/tests
sudo pytest --imgname=docker-sonic-vs:latest -v test_port.py
```

## Fallback: Current Docker genrule approach

If native cc_library proves too complex for a specific package,
keep the Docker genrule as fallback. The image assembly (Phase 5)
works with either approach — it just takes .deb or tar inputs.
