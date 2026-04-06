"""Layer stripping and size reduction rules for SONiC OCI images.

These rules enforce Phase 3 dependency trimming requirements:
  - Strip debug symbols from all shared libraries and binaries
  - Remove doc/man/locale artifacts that dpkg excludes may have missed
  - Remove Python bytecode caches (__pycache__)
  - Verify the resulting layer is within its size budget

Usage:
    stripped_layer(
        name = "my_stripped_layer",
        src = ":my_raw_layer",
        size_budget_mb = 150,
    )
"""

def _stripped_layer_impl(ctx):
    input_tar = ctx.file.src
    output_tar = ctx.actions.declare_file(ctx.attr.name + ".tar")
    size_budget = ctx.attr.size_budget_mb

    ctx.actions.run_shell(
        inputs = [input_tar],
        outputs = [output_tar],
        command = """
set -euo pipefail
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Unpack the layer
tar -xf {input} -C "$WORK"

# Strip debug symbols from all ELF binaries and shared libraries
find "$WORK" -type f \\( -name '*.so' -o -name '*.so.*' \\) -exec strip --strip-debug {{}} \\; 2>/dev/null || true
find "$WORK" -type f -executable -exec sh -c 'file "$1" | grep -q "ELF" && strip --strip-all "$1"' _ {{}} \\; 2>/dev/null || true

# Remove documentation, man pages, locale data (belt and suspenders with dpkg excludes)
rm -rf "$WORK"/usr/share/man \
       "$WORK"/usr/share/info \
       "$WORK"/usr/share/doc \
       "$WORK"/usr/share/groff \
       "$WORK"/usr/share/lintian \
       "$WORK"/usr/share/linda \
       "$WORK"/usr/share/locale \
       "$WORK"/usr/share/i18n \
       "$WORK"/usr/share/bash-completion \
       "$WORK"/usr/share/vim \
       "$WORK"/var/cache/man 2>/dev/null || true

# Remove Python bytecode caches
find "$WORK" -type d -name __pycache__ -exec rm -rf {{}} + 2>/dev/null || true
find "$WORK" -name '*.pyc' -delete 2>/dev/null || true

# Remove apt caches and dpkg status files (not needed at runtime)
rm -rf "$WORK"/var/cache/apt \
       "$WORK"/var/lib/apt/lists \
       "$WORK"/var/log/*.log 2>/dev/null || true

# Produce deterministic output tar (--sort may not be available on macOS)
if tar --sort=name -cf /dev/null --files-from /dev/null 2>/dev/null; then
  SOURCE_DATE_EPOCH=0 tar --sort=name --mtime=@0 --owner=0 --group=0 -C "$WORK" -cf {output} .
else
  SOURCE_DATE_EPOCH=0 tar -cf {output} -C "$WORK" .
fi

# Size budget enforcement
SIZE_MB=$(( $(stat -f%z {output} 2>/dev/null || stat -c%s {output}) / 1048576 ))
if [ "$SIZE_MB" -gt {budget} ]; then
  echo "FAIL: layer {name} is ${{SIZE_MB}} MB, exceeds {budget} MB budget"
  exit 1
fi
echo "Layer {name}: ${{SIZE_MB}} MB (budget: {budget} MB)"
""".format(
            input = input_tar.path,
            output = output_tar.path,
            budget = size_budget,
            name = ctx.attr.name,
        ),
        mnemonic = "StripLayer",
        progress_message = "Stripping layer %s (budget: %d MB)" % (ctx.attr.name, size_budget),
    )

    return [DefaultInfo(files = depset([output_tar]))]

stripped_layer = rule(
    implementation = _stripped_layer_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".tar", ".tar.gz"],
            mandatory = True,
            doc = "Input layer tar to strip.",
        ),
        "size_budget_mb": attr.int(
            mandatory = True,
            doc = "Maximum allowed size in MB. Build fails if exceeded.",
        ),
    },
)
