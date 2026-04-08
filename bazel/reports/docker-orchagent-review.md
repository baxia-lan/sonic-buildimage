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
- it now includes `arp_update_vars.j2`
- it now includes `/etc/sonic/constants.yml`
- it now includes local-source installs for `scapy`, `sonic-py-common`, and `redis-dump-load`
- it now includes locally built `swsscommon`, `sonic-db-cli`, and `swssloglevel` from `sonic-swss-common`
- it now includes local-source `sonic-cfggen` from `sonic-config-engine`
- it now generates `/usr/bin/docker-init.real.sh` from `docker-init.j2` during the image build
- it now prunes non-runtime `sonic-config-engine` test data and strips the local `swsscommon` binaries
- it is flattened to a single image layer for review of phase 2 layer reduction
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
docker run --rm --platform linux/amd64 --entrypoint /bin/bash <loaded-image-tag> -lc \
  'set -euo pipefail; \
   test -x /usr/bin/orchagent.sh; \
   test -f /usr/share/sonic/templates/arp_update.conf; \
   test -f /usr/share/sonic/templates/arp_update_vars.j2; \
   test -f /etc/sonic/constants.yml; \
   python3 -c "import jinja2, netaddr, redisdl, scapy; from lxml import etree; from swsscommon import swsscommon; from sonic_py_common import device_info"; \
   sonic-db-cli -h >/dev/null; \
   swssloglevel -h >/dev/null; \
   sonic-cfggen -a "{\"ENABLE_ASAN\":\"n\"}" -t /usr/share/sonic/templates/docker-init.j2,/tmp/docker-init.generated.sh; \
   /bin/bash -n /tmp/docker-init.generated.sh; \
   test -x /usr/bin/docker-init.real.sh'
```

Check the flattened image metadata:

```bash
docker inspect <loaded-image-tag> --format \
  '{{len .RootFS.Layers}} layers {{.Architecture}} {{json .Config.Entrypoint}}'
```

## Current Verified Artifact

The current locally verified artifact is:

- archive: `bazel-bin/images/oci/docker-orchagent/docker-orchagent.gz`
- compressed size: about `84M`
- SHA256: `0ba7ba451d099e7e99a4d37e0f064215ac67afc6665fba3ec002988731874f64`
- loaded image size: about `260MB`
- loaded image shape: `1` rootfs layer, `linux/amd64`

## Current Limitations

- The concrete review builder still uses Docker Buildx locally
- The review Dockerfile still installs packages with `apt-get` and `pip`
- local-source packaging is still review-only glue rather than final Bazel-owned package rules
- The review image supports non-YANG `sonic-cfggen` rendering paths only
- Full SWSS/SAI/config-engine runtime parity is not complete yet
- This target is marked `manual` because it is a review path, not the final CI-default image builder
