# GCP CI Skeleton

This directory holds the Bazel-era GCP CI entrypoints for `sonic-buildimage`.

## Intended Topology

- Cloud Build private pools
  - primary: `us-central1`
  - hot standby: `us-east1`
- Artifact Registry
  - release location: `us` multi-region
- Bazel remote infrastructure
  - self-hosted remote cache
  - self-hosted remote execution
  - both deployed on GKE regional clusters
- Azure Pipelines
  - secondary platform
  - must consume Bazel-exported `target/` artifacts instead of invoking Make

## Pipelines

- `cloudbuild-presubmit.yaml`
  - affected-target build/test
  - lockfile validation
  - no-egress validation
  - baseline artifact inventory generation
  - migrated source ownership validation
  - platform and installer coverage validation
  - image depth/layer regression checks
- `cloudbuild-nightly.yaml`
  - recurring broad build/test matrix
  - refreshed Make-era artifact inventory baseline
  - migrated source ownership validation
  - platform and installer coverage validation
  - image depth/layer regression checks
- `cloudbuild-repro.yaml`
  - same-commit reproducibility check

## Required Substitutions

The Cloud Build configs assume these substitutions are provided:

- `_PRIMARY_POOL`
- `_SECONDARY_POOL`
- `_AFFECTED_LABELS`
- `_NIGHTLY_LABELS`
- `_REPRO_LABELS`

These files are scaffolding for the migration foundation. The concrete label
lists should be tightened as real package, image, and installer Bazel targets
land.
