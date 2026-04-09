# SWSS Pytest Smoke For `docker-sonic-vs`

## Goal

Validate that the Bazel-built `docker-sonic-vs:latest` image boots far enough
for a meaningful SWSS DVS smoke test to pass.

The narrowest useful smoke in this repo is:

- `src/sonic-swss/tests/test_admin_status.py::TestAdminStatus::test_PortHostTxReadiness`

Why this one:

- it starts the DVS-backed test harness
- it exercises `swss`, `orchagent`, Redis databases, and the image's runtime
  config path
- it verifies both admin state propagation and `host_tx_ready` behavior
- it is small enough to use as the first post-build gate before broader SWSS
  coverage

## Recommended Command

Run from the `sonic-swss` test directory:

```bash
cd src/sonic-swss/tests
sudo pytest -sv --force-flaky --max_cpu 2 \
  --imgname=docker-sonic-vs:latest \
  test_admin_status.py::TestAdminStatus::test_PortHostTxReadiness
```

## Runtime Prerequisites

- The Bazel-built image must already be loaded into Docker as
  `docker-sonic-vs:latest`.
- Docker daemon must be reachable from the test host.
- Host must be Linux with the SWSS DVS prerequisites described in
  `src/sonic-swss/tests/README.md`.
- `python3`, `pytest`, `flaky`, `docker`, and the SWSS Python/runtime
  dependencies must be installed on the host.
- The host should have a suitable kernel/module setup for the DVS environment,
  including the `team` module mentioned in the SWSS test README.
- Use `--max_cpu 2` to keep the DVS footprint small and consistent.

## Optional Fallbacks

- If the DVS container aborts because it sees too few ports, rerun with:

```bash
sudo pytest -sv --force-flaky --max_cpu 2 \
  --forcedvs \
  --imgname=docker-sonic-vs:latest \
  test_admin_status.py::TestAdminStatus::test_PortHostTxReadiness
```

- If you want to keep the container alive for debugging, add `--keeptb`.

## What This Does Not Cover

- It is not a full SWSS regression suite.
- It is not a hardware-ASIC test.
- It does not replace broader `pytest` coverage once the image is stable.
