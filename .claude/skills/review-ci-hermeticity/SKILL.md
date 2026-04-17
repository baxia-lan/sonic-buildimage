---
name: review-ci-hermeticity
description: Review CI and Cloud Build for repo mutation, non-hermetic steps, and fake-green paths.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
context: fork
agent: ci-integrity-reviewer
---

Review CI as a verifier of checked-in truth.

Required outputs:
- steps that download or overwrite tracked files
- submodule drift introduced during CI
- hidden success paths such as `exit 0`
- minimal remediation plan
