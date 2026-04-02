# Build `target/docker-orchagent.gz` From a Fresh Clone

## Scope

This flow builds the current Bazel Phase 1 review artifact for `docker-orchagent.gz`.

It produces a real Docker archive and exports it to a legacy-compatible `target/`
path. It is intended for review and migration validation, not yet final runtime
parity.

## Prerequisites

- Git
- Docker with `buildx`
- Network access for Docker base image and package resolution

## Clone

Clone the fork and switch to the Bazel migration branch:

```bash
git clone git@github.com:baxia-lan/sonic-buildimage.git
cd sonic-buildimage
git checkout codex/codex
git submodule update --init --recursive
```

## Build

Set the SONiC platform selection and run the Bazel targets:

```bash
export PLATFORM=broadcom

./tools/bazel/bazelw --batch build --config=ci \
  //images/oci/docker-orchagent:review_archive \
  //images/oci/docker-orchagent:target_tree
```

Notes:

- `PLATFORM=broadcom` is kept in the workflow for SONiC consistency
- the current Phase 1 review target is still selected by Bazel label, not by the
  `PLATFORM` variable itself

## Outputs

The build writes:

- `bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz`
- `bazel-bin/images/oci/docker-orchagent/target_tree/target/docker-orchagent.gz`

The second path is the compatibility export that matches the old `target/`
layout.

## Optional Local Verification

Load the archive:

```bash
docker load -i bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz
```

Run a quick file check:

```bash
docker run --rm --entrypoint /bin/sh <loaded-image-tag> -c \
  'test -x /usr/bin/orchagent.sh && test -f /usr/share/sonic/templates/arp_update.conf'
```

## Current Limitations

- this is a Bazel-built review archive, not yet the final hermetic SONiC image
- the concrete builder still uses Docker Buildx locally
- the review Dockerfile still performs `apt-get` and `pip` installation
- full SWSS, SAI, and config-engine runtime parity is still in progress
