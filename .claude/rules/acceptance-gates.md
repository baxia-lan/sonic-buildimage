---
paths:
  - "acceptance/**/*"
---

# Acceptance gate rules

1. Distinguish clearly between:
   - package-level verification
   - image-level verification
   - repo-final acceptance gates

2. Acceptance scripts must test real labels and real artifacts.
   Placeholder labels or expected-failure stubs do not count.

3. If `acceptance/BUILD.bazel` advertises an aggregate target, it must actually exist.

4. Every acceptance result should report:
   - exact target
   - exact command
   - artifact built or loaded
   - service/test evidence
   - known partial coverage

5. Never claim repo completion from a package-local pass.

6. Passing an acceptance gate does not authorize deleting Make.
   Bazel acceptance and Make preservation are separate requirements.
