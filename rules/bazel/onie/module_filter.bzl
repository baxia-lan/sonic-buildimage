"""Kernel module filtering rule for ONIE image size reduction.

Phase 3: Only kernel modules listed in the platform's modules.allowlist
are included in the final ONIE installer image. All other .ko files are
stripped, saving 20-40 MB per platform image.

Usage:
    filtered_modules(
        name = "broadcom_modules",
        modules_tar = "//src/sonic-linux-kernel:modules.tar.gz",
        allowlist = "//platform/broadcom:modules.allowlist",
        size_budget_mb = 60,
    )
"""

def _filtered_modules_impl(ctx):
    modules_tar = ctx.file.modules_tar
    allowlist = ctx.file.allowlist
    output = ctx.actions.declare_file(ctx.attr.name + ".tar.gz")
    budget = ctx.attr.size_budget_mb

    ctx.actions.run_shell(
        inputs = [modules_tar, allowlist],
        outputs = [output],
        command = """
set -euo pipefail
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Unpack all modules
tar -xf {modules_tar} -C "$WORK"

# Build the allowlist set
ALLOW="$WORK/.allowlist"
grep -v '^#' {allowlist} | grep -v '^$' | sed 's/$/.ko/' > "$ALLOW"

# Remove modules NOT in the allowlist
REMOVED=0
KEPT=0
find "$WORK" -name '*.ko' | while read ko; do
  basename=$(basename "$ko")
  if ! grep -qF "$basename" "$ALLOW"; then
    rm -f "$ko"
    REMOVED=$((REMOVED + 1))
  else
    KEPT=$((KEPT + 1))
  fi
done

# Clean empty directories left after removal
find "$WORK" -type d -empty -delete 2>/dev/null || true

# Rebuild modules.dep for the remaining modules
if command -v depmod >/dev/null 2>&1; then
  KVER=$(ls "$WORK/lib/modules/" 2>/dev/null | head -1)
  if [ -n "$KVER" ]; then
    depmod -b "$WORK" "$KVER" 2>/dev/null || true
  fi
fi

# Create output tar
SOURCE_DATE_EPOCH=0 tar \\
  --sort=name --mtime=@0 \\
  --owner=0 --group=0 \\
  -czf {output} -C "$WORK" .

# Size check
SIZE_MB=$(( $(stat -f%z {output} 2>/dev/null || stat -c%s {output}) / 1048576 ))
if [ "$SIZE_MB" -gt {budget} ]; then
  echo "FAIL: filtered modules are $SIZE_MB MB, exceeds {budget} MB budget"
  exit 1
fi
echo "Filtered modules: $SIZE_MB MB (budget: {budget} MB)"
""".format(
            modules_tar = modules_tar.path,
            allowlist = allowlist.path,
            output = output.path,
            budget = budget,
        ),
        mnemonic = "FilterModules",
        progress_message = "Filtering kernel modules for %s" % ctx.attr.name,
    )

    return [DefaultInfo(files = depset([output]))]

filtered_modules = rule(
    implementation = _filtered_modules_impl,
    attrs = {
        "modules_tar": attr.label(
            allow_single_file = [".tar", ".tar.gz"],
            mandatory = True,
            doc = "Input tar containing all kernel modules.",
        ),
        "allowlist": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Text file listing allowed module names (one per line, without .ko).",
        ),
        "size_budget_mb": attr.int(
            default = 60,
            doc = "Maximum allowed size in MB. Build fails if exceeded.",
        ),
    },
)
