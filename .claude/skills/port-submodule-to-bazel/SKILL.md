---
name: port-submodule-to-bazel
description: Port one sonic-buildimage submodule or package boundary from Make wiring to a narrow Bazel implementation without removing or weakening existing Make flow.
argument-hint: [submodule-path-or-target]
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Edit Write
context: fork
agent: bazel-build-writer
---

Port this migration unit to Bazel:

$ARGUMENTS

Goal:
Add a narrow, reviewable Bazel implementation for the requested unit.
Preserve the original Make system. Do not remove, rename, or weaken existing Make wiring.

Process:
1. Reconfirm the mapping first.
   If dependency ownership or output shape is unclear, stop and analyze before writing.

2. Choose the smallest credible Bazel package boundary.

3. Add or update only the necessary files:
   - `BUILD.bazel`
   - `BUILD`
   - `.bzl`
   - adjacent helper files only when required

4. Prefer explicit labels and direct deps.
   Avoid introducing new repo-wide abstractions on the first pass.

5. Keep separate concerns separate:
   - source/library build
   - generated outputs
   - packaging
   - docker/image integration

6. Respect existing platform boundaries.
   Only encode selects/config_settings when you can point to an existing platform split in Make/platform files.

7. Keep edits small and reviewable.

Before finishing, provide:
- files changed
- labels added or changed
- assumptions
- what remains Make-owned
- whether original Make rules were preserved
- exact narrow verification command(s)
- follow-up items that should be separate changes
