---
name: verify-bazel-package
description: Verify one Bazel package or label narrowly and report dependency, query, and parity issues relevant to sonic-buildimage migration.
argument-hint: [bazel-label-or-package]
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
context: fork
agent: build-graph-explorer
---

Verify this Bazel package or label:

$ARGUMENTS

Goal:
Run the narrowest useful verification for the requested Bazel target/package and report what still blocks parity.

Rules:
1. Prefer the narrowest command that answers the question:
   - `bazel query`
   - `bazel cquery`
   - `bazel build <label>`
   - package-local checks
2. Do not run repo-wide builds unless explicitly asked.
3. Compare failures back to the current Make-owned graph where useful.
4. Distinguish:
   - missing direct deps
   - package boundary mistakes
   - generated file issues
   - packaging/image integration gaps
   - platform-specific mismatches
5. State whether the original Make rules for this scope remain preserved.

Output format:
## Verification target
## Commands run
## Result
## Missing deps / graph issues
## Packaging or image gaps
## Still Make-owned
## Make preservation status
## Suggested next edit
