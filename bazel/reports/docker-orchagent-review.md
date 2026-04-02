# `docker-orchagent.gz` Bazel Review Artifact

## What Changed

This change adds a Bazel-owned review build path for `docker-orchagent.gz`.

- `//images/oci/docker-orchagent:review_archive` builds a real `docker-orchagent.gz`
- `//images/oci/docker-orchagent:target_tree` exports that archive to a legacy-compatible `target/` layout
- `//tools/bazel:build_review_docker_archive` is the concrete builder used by the Bazel target
- `//dockers/docker-orchagent:review_srcs` and `//files:scripts/arp_update` provide the image inputs

This is intentionally a Phase 1 review artifact:

- it is a real Docker archive produced by Bazel
- it can be loaded and run with Docker
- it carries the current `docker-orchagent` scripts and templates
- it is not yet the final hermetic SONiC runtime image

## How To Build

Run:

```bash
./tools/bazel/bazelw --batch build --config=ci \
  //images/oci/docker-orchagent:review_archive \
  //images/oci/docker-orchagent:target_tree
```

## Output Files

After the build completes, the outputs are:

- `bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz`
- `bazel-bin/images/oci/docker-orchagent/target_tree/target/docker-orchagent.gz`

The second path is the compatibility export that matches the old `target/` shape.

## Optional Verification

Load the archive:

```bash
docker load -i bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz
```

Run a quick check:

```bash
docker run --rm --entrypoint /bin/sh <loaded-image-tag> -c \
  'test -x /usr/bin/orchagent.sh && test -f /usr/share/sonic/templates/arp_update.conf'
```

## Current Limitations

- The concrete review builder still uses Docker Buildx locally
- The review Dockerfile still installs packages with `apt-get` and `pip`
- Full SWSS/SAI/config-engine runtime parity is not complete yet
- This target is marked `manual` because it is a review path, not the final CI-default image builder
