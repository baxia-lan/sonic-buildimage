---
paths:
  - "cloudbuild.yaml"
  - ".github/workflows/**/*"
  - "acceptance/**/*"
---

# CI and acceptance integrity rules

1. CI must validate checked-in repo state, not synthesize a different repo.
2. Do not download replacement `BUILD.bazel`, `MODULE.bazel`, `config.h`, or similar tracked files from external repos during CI.
3. Do not `git checkout` submodules to arbitrary SHAs inside CI to make Bazel pass.
4. If a gate is partial, placeholder, or advisory, name it explicitly.
   Do not label it as a hard acceptance gate until it is actually enforcing the intended contract.
5. Acceptance scripts must reference real Bazel labels.
   If labels drift, fix the contract before claiming progress.
6. CI changes require both:
   - the changed CI file diff,
   - evidence of the exact commands exercised.
7. Do not delete or weaken original Make paths in CI as part of Bazel migration.
