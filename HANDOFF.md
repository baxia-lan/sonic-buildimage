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
- the container imports `swsscommon`, `sonic_py_common`, `scapy`, and `redisdl`
- `sonic-db-cli -h` runs in the container
- `swssloglevel -h` runs in the container
- current artifact size is about `93M` compressed and `300MB` loaded
- current artifact SHA256 is `bd439ce593217a2394407644c4a2765c0ef6dc873e0a76dc77a0855cb2caf209`

## Known Gaps

- the concrete image builder still depends on Docker Buildx
- the review Dockerfile still uses `apt-get` and `pip`
- `sonic-swss-common` source exposure currently depends on Bazel metadata added in that submodule
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
