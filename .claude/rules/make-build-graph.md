---
paths:
  - "Makefile"
  - "Makefile.*"
  - "**/*.mk"
  - "rules/**/*"
  - "platform/**/*.mk"
  - "dockers/**/Dockerfile*"
  - ".gitmodules"
---

# Make / recipe graph analysis

When working with Makefiles, recipe files, submodule wiring, or package definitions:

1. Build a mapping table with these columns:
   - Make target / package variable
   - source path
   - builder shape
   - direct build deps
   - runtime/image deps
   - outputs
   - platform-specific branches

2. Resolve these patterns explicitly when present:
   - `*_SRC_PATH`
   - `*_DEPENDS`
   - `*_RDEPENDS`
   - `*_PATH`
   - `*_URL`
   - target-group membership such as:
     - `SONIC_DPKG_DEBS`
     - `SONIC_PYTHON_STDEB_DEBS`
     - `SONIC_MAKE_DEBS`
     - docker/image groups
     - copy/download groups

3. Do not stop at the first assignment.
   Trace includes, variable indirection, and derived-package helpers.

4. Distinguish:
   - build-time deps
   - runtime install deps
   - image composition deps
   - fetched/prebuilt artifacts

5. If the target is produced by Make but sourced from a submodule, inspect:
   - `.gitmodules`
   - the submodule root
   - any `debian/` packaging files
   - scripts or patches used before packaging

6. Before proposing Bazel, identify the smallest credible Bazel package boundary.

7. Default posture is preservation:
   - keep original Make rules
   - do not propose deleting `.mk` / `Makefile` paths
   - report how Bazel will coexist with Make
