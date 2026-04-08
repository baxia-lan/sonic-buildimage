# Handoff

## Current State

The repository now contains a Bazel Phase 1 review path for
`docker-orchagent.gz`.

This path produces a real Docker archive:

- Bazel target: `//images/oci/docker-orchagent:review_archive`
- legacy export: `//images/oci/docker-orchagent:target_tree`
- exported file: `target/docker-orchagent.gz`
- current review image shape: single-layer `linux/amd64`
- current review image contents include local-source `scapy`,
  `sonic-py-common`, `redis-dump-load`, and locally built
  `swsscommon` / `sonic-db-cli` / `swssloglevel`
- current review image contents also include local-source
  `sonic-cfggen` / `sonic-config-engine`, `/etc/sonic/constants.yml`,
  and a generated `/usr/bin/docker-init.real.sh`
- current review image prunes non-runtime `sonic-config-engine` tests/docs and
  strips the locally built `swsscommon` runtime binaries

This is a concrete artifact for review. It is not the final hermetic SONiC
runtime image yet.

## Main Files

- `images/oci/docker-orchagent/BUILD.bazel`
- `src/BUILD.bazel`
- `src/sonic-swss-common/BUILD.bazel`
- `src/sonic-swss-common/tests/BUILD`
- `tools/bazel/build_review_docker_archive.sh`
- `tools/bazel/export_target_tree.sh`
- `dockers/docker-orchagent/BUILD.bazel`
- `files/BUILD.bazel`
- `bazel/sonic/private/artifacts.bzl`
- `bazel/sonic/private/export.bzl`
- `bazel/sonic/private/sources.bzl`
- `bazel/reports/docker-orchagent-review.md`
- `bazel/reports/docker-orchagent-build-from-clone.md`

## How To Build

From a fresh clone:

```bash
git clone git@github.com:baxia-lan/sonic-buildimage.git
cd sonic-buildimage
git checkout codex/codex
git submodule update --init --recursive

export PLATFORM=broadcom

./tools/bazel/bazelw --batch build --config=ci \
  //images/oci/docker-orchagent:review_archive \
  //images/oci/docker-orchagent:target_tree
```

Outputs:

- `bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz`
- `bazel-bin/images/oci/docker-orchagent/target_tree/target/docker-orchagent.gz`

## What Was Verified

- Bazel successfully built `docker-orchagent.gz`
- Bazel successfully exported `target/docker-orchagent.gz`
- the archive passed `gzip -t`
- the archive could be loaded with `docker load -i`
- the loaded image could be run locally
- the flattened image now reports `1` rootfs layer
- the flattened image now preserves `amd64` architecture metadata
- the container contains `/usr/bin/orchagent.sh`
- the container contains `/usr/share/sonic/templates/arp_update.conf`
- the container contains `/usr/share/sonic/templates/arp_update_vars.j2`
- the container contains `/etc/sonic/constants.yml`
- the container imports `jinja2`, `netaddr`, `lxml`, `swsscommon`,
  `sonic_py_common`, `scapy`, and `redisdl`
- `sonic-db-cli -h` runs in the container
- `swssloglevel -h` runs in the container
- `sonic-cfggen` renders `docker-init.j2` in the container
- `/usr/bin/docker-init.real.sh` exists and passes `/bin/bash -n`
- `supervisord` remains present at `/usr/bin/supervisord`
- current artifact size is about `84M` compressed and `260MB` loaded
- current artifact SHA256 is `0ba7ba451d099e7e99a4d37e0f064215ac67afc6665fba3ec002988731874f64`

## Known Gaps

- the concrete image builder still depends on Docker Buildx
- the review Dockerfile still uses `apt-get` and `pip`
- `sonic-swss-common` source exposure currently depends on Bazel metadata added in that submodule
- the current review image only supports non-YANG `sonic-cfggen` paths
- the image is suitable for structure and dependency review, not yet full SONiC
  runtime parity
- the target is intentionally tagged `manual` and is not yet the final CI-default
  image builder

## Recommended Next Steps

1. Replace ad hoc package installation in the review builder with Bazel-owned
   package inputs.
2. Move from review archive content to real runtime parity with the current
   SONiC `docker-orchagent` container.
3. Collapse remaining intermediate image layering into the final service image
   shape.
4. Promote the concrete image builder from manual review target to the default
   Bazel image path after runtime validation is complete.
