# Make→Bazel Migration Progress

Last updated: 2026-04-10

## Milestone 1: docker-sonic-vs + pytest

| Item | Status | Actually Verified? |
|---|---|---|
| OCI image assembly | Builds | CI build succeeded |
| .deb chain (libnl3→swss-common→sairedis→swss) | Builds | 28 .debs in CI |
| FRR 10.6.0 | Fetches at build time | sha256 pinned |
| Python layer (sonic-cfggen) | Builds | CI build succeeded |
| Config (supervisord, redis, device data) | Builds | CI build succeeded |
| Image loads into Docker | **UNKNOWN** | CI step passed but pytest wasn't installed |
| pytest test_port.py | **NOT RUN** | `pytest: command not found` — fix pushed |

**Not hermetic**: .deb compilation uses Docker genrules. FRR from external repo. Python layer uses Docker.

## Milestone 2: Cloud Build

| Item | Status |
|---|---|
| cloudbuild.yaml | Written, 12 steps |
| First successful run | **UNKNOWN** — no GCP access to check |

## Milestone 3: sonic-broadcom.bin

| Item | Status | Actually Verified? |
|---|---|---|
| Kernel compilation | Works | 66MB linux-image .deb in CI |
| vmlinuz extraction | Fix pushed | **NOT VERIFIED** — previous CI used cached stub |
| broadcom.bin assembly | Builds | 7MB (STUB — not real kernel) |
| broadcom.bin with real kernel | **NOT DONE** | Fix pushed to build vmlinuz first |

## What Is Actually Hermetic

| Component | Hermetic? | Why Not |
|---|---|---|
| 9 Docker service images | Yes | rules_distroless + oci_image |
| .deb compilation | **No** | Docker genrule + dpkg-buildpackage |
| FRR | Partial | Downloaded at fetch time, sha256 pinned |
| Python packages | **No** | Docker genrule + pip install |
| Kernel | **No** | Docker genrule + make |
| OCI image assembly | Yes | oci_image + pkg_tar |

## CI Run Status

Waiting for run 24255339706 with:
- `sudo pip3 install pytest` (pytest was missing)
- Explicit vmlinuz build before broadcom.bin
