---
paths:
  - "BUILD"
  - "**/BUILD"
  - "BUILD.bazel"
  - "**/BUILD.bazel"
  - "**/*.bzl"
  - "bazel/**/*"
  - "MODULE.bazel"
  - "tools/bazel/**/*"
---

# Bazel migration rules

When editing Bazel files for this repo:

1. Keep first migrations local and explicit.
   Favor a small BUILD file near the real source directory over a central mega-macro.

2. Preserve current Make ownership until parity is proven.
   Adding Bazel is preferred to deleting Make wiring.

3. Preserve original Make files and rule structure.
   Do not delete or weaken `.mk`, `Makefile`, or Make-owned helpers as part of ordinary migration work.

4. Separate layers when possible:
   - source/library
   - generated files
   - packaging
   - docker/image assembly

5. Avoid hiding new logic in opaque shell commands unless the repo already relies on that boundary
   and a structured Bazel rule is not practical yet.

6. Platform conditionals must be justified by an existing Make/platform split.
   Do not invent new axes of variability.

7. After editing Bazel files, always state:
   - new labels
   - package boundaries
   - assumptions
   - narrowest verification command
   - what remains Make-owned
   - whether original Make rules were preserved

8. Repository rules may download pinned inputs. Build actions may not.
