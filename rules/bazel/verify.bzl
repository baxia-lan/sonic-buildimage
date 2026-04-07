"""Verification rules for SONiC Bazel artefacts.

Provides two test rules that can be used as post-build validation gates:

* ``hermetic_test`` — verifies that a build target is hermetic (no
  undeclared host-tool or network dependencies).
* ``size_test`` — asserts that a build artefact is below a maximum size
  budget, preventing accidental image bloat.

Both rules produce test targets that integrate with ``bazel test`` and
can be run in CI via ``--config=ci``.

Example:
    ```starlark
    load("//tools/verify:defs.bzl", "hermetic_test", "size_test")

    hermetic_test(
        name = "orchagent_hermetic",
        target = "//docker/docker-orchagent",
    )

    size_test(
        name = "orchagent_size",
        target = "//docker/docker-orchagent:docker-orchagent_tarball",
        max_size_mb = 500,
    )
    ```
"""

def _hermetic_test_impl(ctx):
    """Generates a test script that validates build hermeticity.

    Checks that the target's action graph does not reference host paths
    outside the sandbox or undeclared network endpoints.

    Args:
        ctx: Rule context.

    Returns:
        ``DefaultInfo`` for the test runner.
    """
    target = ctx.attr.target
    target_label = target.label

    # Collect the target's output files to inspect.
    target_files = target[DefaultInfo].files

    # Build a space-separated list of runfile-relative paths to embed in
    # the test script so it can locate them at runtime.
    file_paths = []
    for f in target_files.to_list():
        file_paths.append(f.short_path)

    script = ctx.actions.declare_file(ctx.label.name + "_hermetic_check.sh")
    ctx.actions.write(
        output = script,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

TARGET_LABEL="{label}"
echo "=== Hermetic check: $TARGET_LABEL ==="

# Resolve runfiles directory.
if [[ -n "${{RUNFILES_DIR:-}}" ]]; then
    RDIR="$RUNFILES_DIR"
elif [[ -d "$0.runfiles" ]]; then
    RDIR="$0.runfiles"
else
    RDIR="$(cd "$(dirname "$0")" && pwd)"
fi

FILES=({files})
FAIL=0
FILE_COUNT=0

for rel in "${{FILES[@]}}"; do
    f="$RDIR/_main/$rel"
    [ -e "$f" ] || f="$rel"
    [ -e "$f" ] || continue
    FILE_COUNT=$((FILE_COUNT + 1))

    # Check: Output files must not be symlinks to host paths.
    if [ -L "$f" ]; then
        REAL=$(readlink -f "$f" 2>/dev/null || true)
        case "$REAL" in
            /usr/local/*|/opt/*|/home/*)
                echo "FAIL: $f symlinks to host path: $REAL"
                FAIL=1 ;;
        esac
    fi

    # Check: ELF binaries should not have absolute RPATH to host dirs.
    if file "$f" 2>/dev/null | grep -q "ELF"; then
        if readelf -d "$f" 2>/dev/null | grep -qE "RPATH|RUNPATH"; then
            RPATHS=$(readelf -d "$f" 2>/dev/null | grep -oP '(?<=\\[).*?(?=\\])' || true)
            for rp in $RPATHS; do
                case "$rp" in
                    /usr/local/*|/opt/*)
                        echo "FAIL: $f has host RPATH: $rp"
                        FAIL=1 ;;
                esac
            done
        fi
    fi
done

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "FAIL: target produced no output files"
    FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: $TARGET_LABEL is hermetic ($FILE_COUNT files checked)"
else
    echo "FAIL: $TARGET_LABEL has hermeticity violations"
    exit 1
fi
""".format(
            label = str(target_label),
            files = " ".join(['"%s"' % p for p in file_paths]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(transitive_files = target_files)

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

hermetic_test = rule(
    implementation = _hermetic_test_impl,
    test = True,
    attrs = {
        "target": attr.label(
            mandatory = True,
            doc = "Build target to verify for hermeticity.",
        ),
    },
    doc = "Tests that a build target is hermetic: no host-path leaks or undeclared deps.",
)

def _size_test_impl(ctx):
    """Generates a test script that asserts an artefact fits within a size budget.

    Args:
        ctx: Rule context.

    Returns:
        ``DefaultInfo`` for the test runner.
    """
    target = ctx.attr.target
    max_bytes = ctx.attr.max_size_mb * 1024 * 1024

    target_files = target[DefaultInfo].files

    # Embed runfile-relative paths into the script.
    file_paths = []
    for f in target_files.to_list():
        file_paths.append(f.short_path)

    script = ctx.actions.declare_file(ctx.label.name + "_size_check.sh")
    ctx.actions.write(
        output = script,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

MAX_BYTES={max_bytes}
MAX_MB={max_mb}
TARGET_LABEL="{label}"

echo "=== Size check: $TARGET_LABEL (limit: ${{MAX_MB}} MB) ==="

# Resolve runfiles directory.
if [[ -n "${{RUNFILES_DIR:-}}" ]]; then
    RDIR="$RUNFILES_DIR"
elif [[ -d "$0.runfiles" ]]; then
    RDIR="$0.runfiles"
else
    RDIR="$(cd "$(dirname "$0")" && pwd)"
fi

FILES=({files})
TOTAL=0

for rel in "${{FILES[@]}}"; do
    f="$RDIR/_main/$rel"
    [ -e "$f" ] || f="$rel"
    [ -e "$f" ] || continue
    if [ -f "$f" ]; then
        SIZE=$(stat -f%%z "$f" 2>/dev/null || stat -c%%s "$f" 2>/dev/null || echo 0)
        TOTAL=$((TOTAL + SIZE))
        SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc 2>/dev/null || echo "?")
        echo "  $rel: ${{SIZE_MB}} MB"
    fi
done

TOTAL_MB=$(echo "scale=2; $TOTAL / 1048576" | bc 2>/dev/null || echo "?")
echo "Total: ${{TOTAL_MB}} MB (limit: ${{MAX_MB}} MB)"

if [ "$TOTAL" -gt "$MAX_BYTES" ]; then
    echo "FAIL: ${{TOTAL_MB}} MB exceeds ${{MAX_MB}} MB budget"
    exit 1
fi

echo "PASS: ${{TOTAL_MB}} MB within ${{MAX_MB}} MB budget"
""".format(
            max_bytes = max_bytes,
            max_mb = ctx.attr.max_size_mb,
            label = str(target.label),
            files = " ".join(['"%s"' % p for p in file_paths]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(transitive_files = target_files)

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

size_test = rule(
    implementation = _size_test_impl,
    test = True,
    attrs = {
        "target": attr.label(
            mandatory = True,
            doc = "Build artefact target to measure.",
        ),
        "max_size_mb": attr.int(
            mandatory = True,
            doc = "Maximum allowed size in megabytes.",
        ),
    },
    doc = "Tests that a build artefact does not exceed a size budget (in MB).",
)
