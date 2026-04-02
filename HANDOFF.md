# Handoff

## Current State

The repository now contains a Bazel Phase 1 review path for
`docker-orchagent.gz`.

This path produces a real Docker archive:

- Bazel target: `//images/oci/docker-orchagent:review_archive`
- legacy export: `//images/oci/docker-orchagent:target_tree`
- exported file: `target/docker-orchagent.gz`

This is a concrete artifact for review. It is not the final hermetic SONiC
runtime image yet.

## Main Files

- `images/oci/docker-orchagent/BUILD.bazel`
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
- the container contains `/usr/bin/orchagent.sh`
- the container contains `/usr/share/sonic/templates/arp_update.conf`

## Known Gaps

- the concrete image builder still depends on Docker Buildx
- the review Dockerfile still uses `apt-get` and `pip`
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
