---
name: analyze-make-target
description: Analyze one sonic-buildimage Make target, recipe, submodule, or source path and map it to a candidate Bazel package plan.
argument-hint: [make-target-or-path]
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
context: fork
agent: build-graph-explorer
---

Analyze this migration unit:

$ARGUMENTS

Goal:
Produce a precise mapping from the current Make-based build logic to a candidate Bazel package boundary.
Do not edit files.

Required steps:
1. Resolve what the input refers to:
   - make target
   - package variable
   - source path
   - submodule
   - artifact
   - docker/image target

2. Inspect the most relevant files:
   - `README.buildsystem.md`
   - `slave.mk`
   - matching `Makefile` / `.mk`
   - `.gitmodules` if submodule-related
   - submodule root / source dir
   - `debian/` files if packaging is involved
   - Dockerfiles or image wiring if relevant
   - nearby Bazel files if they already exist

3. Determine the builder shape:
   - dpkg-buildpackage
   - stdeb
   - custom make
   - docker build
   - copy/download/prebuilt
   - mixed flow

4. Extract:
   - source roots
   - direct build deps
   - runtime/image deps
   - outputs
   - platform-specific branches or overlays
   - generated artifacts and scripts

5. Propose:
   - Bazel package boundary
   - candidate labels
   - unresolved blockers
   - the smallest safe next implementation step
   - coexistence notes describing how Make remains preserved

Output format:
## Input resolved
## Owner files
## Builder shape
## Direct build deps
## Runtime / image deps
## Outputs
## Candidate Bazel package(s)
## Coexistence notes
## Risks / blockers
## Next safe step
