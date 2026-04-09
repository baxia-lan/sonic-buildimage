# Docker Sonic VS Bazel-Native Status

## Scope

This note records the current state of the Bazel-native migration for
`docker-sonic-vs.gz`.

The target requirement is:

- final artifact built by Bazel rules
- no legacy `make configure`
- no legacy artifact bridge
- no execution-time network fetches in Bazel actions

## What Exists Now

The repository now has Bazel-native building blocks for the final image path:

- Bazel-native OCI packaging in `bazel/sonic/private/builders/oci.bzl`
- Bazel-native Debian package building in
  `bazel/sonic/private/builders/deb.bzl`
- Bazel-native rootfs layer assembly logic in
  `bazel/sonic/private/layers.bzl`
- a Bazel-owned `docker-base-bookworm` image path in
  `images/oci/docker-base-bookworm/BUILD.bazel`
- a Bazel-owned `docker-sonic-vs` image composition skeleton in
  `images/oci/docker-sonic-vs/BUILD.bazel`

## Concrete Progress

The following concrete package migration blocker was fixed:

- `src/sonic-sairedis` no longer requires Python3 SWIG bindings for runtime
  Debian package builds.
- `libsaivs` now builds through the Bazel concrete Debian builder.

Key changes:

- `src/sonic-sairedis/configure.ac`
- `src/sonic-sairedis/pyext/Makefile.am`
- `src/sonic-sairedis/debian/control`
- `src/sonic-sairedis/debian/rules`
- `packages/deb/libsaivs/BUILD.bazel`
- `packages/deb/libsaivs-dev/BUILD.bazel`
- `packages/deb/libsairedis/BUILD.bazel`
- `packages/deb/libsairedis-dev/BUILD.bazel`
- `packages/deb/libsaimetadata/BUILD.bazel`
- `packages/deb/libsaimetadata-dev/BUILD.bazel`
- `packages/deb/syncd-vs/BUILD.bazel`

## Bazel-Native Validation Completed

These commands were validated locally:

```bash
./tools/bazel/bazelw --batch build --config=ci //packages/deb/libsaivs:deb
./tools/bazel/bazelw --batch build --config=ci //images/oci/docker-base-bookworm:image
```

Observed outputs:

- `bazel-bin/packages/deb/libsaivs/libsaivs_1.0.0_amd64.deb`
- `bazel-bin/images/oci/docker-base-bookworm/docker-base-bookworm.gz`

## Current Blocker

`//images/oci/docker-sonic-vs:image` is currently blocked during Bazel analysis
by a host toolchain mismatch triggered by `rules_distroless`.

Current failure shape:

- `gawk` from `@bookworm_runtime` is analyzed as a host C/C++ build input
- Bazel requests
  `@@rules_cc++cc_configure_extension+local_config_cc//:cc-compiler-darwin_arm64`
- the generated `local_config_cc` repository is missing that package

This means the current blocker is not the SONiC runtime content itself. It is a
host-side Bazel toolchain/configuration problem in the `rules_distroless`
flatten path used by `docker-base-bookworm`.

## Next Step

Replace the remaining `rules_distroless.flatten()` usage in the base image path
with the repo-owned Bazel rootfs layer builder so that `docker-sonic-vs.gz`
does not depend on host-side `gawk` compilation during analysis.

Then continue:

1. `//packages/deb/libsairedis:deb`
2. `//packages/deb/libsaimetadata:deb`
3. `//packages/deb/syncd-vs:deb`
4. `//packages/deb/swss:deb`
5. `//images/oci/docker-sonic-vs:image`
6. `docker load -i ...`
7. `swss pytest` smoke
