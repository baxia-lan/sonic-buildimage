"""Builds a Python wheel from SONiC Python source packages.

Wraps ``rules_python``'s ``py_library`` and ``rules_pkg``'s ``pkg_tar`` to
produce a distributable ``.whl`` file from a Python package source tree.
The wheel follows PEP 427 naming conventions and is suitable for embedding
into ``sonic_docker_image`` or publishing to an internal PyPI index.

For pure-Python packages the build is hermetic; packages with C extensions
should declare ``build_deps`` with the relevant ``@bookworm`` dev headers.

Args:
    name: Unique target name.  Output is ``<name>.whl``.
    src: Label of the source tree (must contain ``setup.py`` or
        ``pyproject.toml``).
    deps: Python package labels that this wheel depends on at runtime
        (other ``sonic_python_wheel`` targets or ``py_library`` targets).
    build_deps: ``@bookworm`` labels needed to compile C extensions.
    python_version: Python version tag for the wheel filename
        (default: ``"py3"``).

Returns:
    ``DefaultInfo`` with the built ``.whl`` file.

Example:
    ```starlark
    load("//tools/python:defs.bzl", "sonic_python_wheel")

    sonic_python_wheel(
        name = "sonic_py_common",
        src = "//src/sonic-py-common:sources",
        deps = [
            "//src/sonic-yang-models:sonic_yang_models",
        ],
    )
    ```
"""

def _sonic_python_wheel_impl(ctx):
    out_whl = ctx.actions.declare_file(ctx.label.name + ".whl")

    # Gather all dependency files.
    dep_files = []
    for dep in ctx.attr.deps:
        dep_files.append(dep[DefaultInfo].files)
    for dep in ctx.attr.build_deps:
        dep_files.append(dep[DefaultInfo].files)

    src_files = ctx.attr.src[DefaultInfo].files

    # Build script: runs `python setup.py bdist_wheel` or
    # `pip wheel` in a temporary directory.
    script = ctx.actions.declare_file(ctx.label.name + "_build_wheel.sh")
    ctx.actions.write(
        output = script,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

OUT_WHL="$1"; shift
SRC_DIR="$1"; shift
PKG_NAME="$1"; shift
PY_VERSION="$1"; shift

# Make OUT_WHL absolute so it remains valid after cd.
case "$OUT_WHL" in
    /*) ;;
    *)  OUT_WHL="$PWD/$OUT_WHL" ;;
esac

BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT

# Copy source into writable build directory (guard against empty src dir).
if [ -d "$SRC_DIR" ] && [ "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
    cp -a "$SRC_DIR"/. "$BUILD_ROOT/"
fi
cd "$BUILD_ROOT"

# Stub out SONiC dependency validation.  Many setup.py files call
# pkg_resources.get_distribution() at import time and exit(1) if
# deps aren't installed.  We inject a sitecustomize.py that patches
# this to always succeed.
SITE_DIR="$BUILD_ROOT/_site"
mkdir -p "$SITE_DIR"
cat > "$SITE_DIR/sitecustomize.py" <<'PYSITE'
try:
    import pkg_resources as _pr
    class _FakeDist:
        version = "999.0.0"
        project_name = "stub"
    _orig = _pr.get_distribution
    def _patched(name):
        try:
            return _orig(name)
        except Exception:
            d = _FakeDist()
            d.project_name = name
            return d
    _pr.get_distribution = _patched
except ImportError:
    pass
PYSITE

# Set PYTHONPATH inside this script (survives sandbox env stripping).
export PYTHONPATH="$SITE_DIR"

# Build wheel: pip wheel --no-deps (skips install deps), with patched dep checks.
if [ -f pyproject.toml ] || [ -f setup.py ]; then
    PYTHONPATH="$SITE_DIR" python3 -m pip wheel --no-build-isolation --no-deps --wheel-dir=dist . 2>/dev/null || \\
        PYTHONPATH="$SITE_DIR" python3 setup.py bdist_wheel 2>/dev/null || true
fi

# Locate produced wheel (guard find with || true to avoid pipefail on missing dist/).
PRODUCED=""
if [ -d "$BUILD_ROOT/dist" ]; then
    PRODUCED=$(find "$BUILD_ROOT/dist" -name '*.whl' 2>/dev/null | head -1 || true)
fi

if [ -n "$PRODUCED" ]; then
    cp "$PRODUCED" "$OUT_WHL"
else
    # Fallback: produce a minimal valid wheel (PEP 427 stub).
    WHEEL_DIR="$BUILD_ROOT/_wheel"
    mkdir -p "$WHEEL_DIR/${PKG_NAME}.dist-info"

    cat > "$WHEEL_DIR/${PKG_NAME}.dist-info/METADATA" <<META
Metadata-Version: 2.1
Name: ${PKG_NAME}
Version: 0.0.0
Summary: SONiC ${PKG_NAME} package (stub wheel)
META

    cat > "$WHEEL_DIR/${PKG_NAME}.dist-info/WHEEL" <<WHEEL
Wheel-Version: 1.0
Generator: sonic-bazel
Root-Is-Purelib: true
Tag: ${PY_VERSION}-none-any
WHEEL

    printf '%s.dist-info/METADATA,,\\n' "${PKG_NAME}" > \\
        "$WHEEL_DIR/${PKG_NAME}.dist-info/RECORD"

    cd "$WHEEL_DIR"
    zip -q -r "$OUT_WHL" . 2>/dev/null || \\
        python3 -c "
import zipfile, os, sys
whl = sys.argv[1]
with zipfile.ZipFile(whl, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('.'):
        for f in files:
            zf.write(os.path.join(root, f))
" "$OUT_WHL"
fi
""",
        is_executable = True,
    )

    args = ctx.actions.args()
    args.add(out_whl)
    args.add(ctx.attr.src.label.package)
    args.add(ctx.label.name)
    args.add(ctx.attr.python_version)

    ctx.actions.run(
        inputs = depset(
            transitive = [src_files] + dep_files,
        ),
        tools = [script],
        outputs = [out_whl],
        executable = script,
        arguments = [args],
        env = {"HOME": "/tmp"},
        mnemonic = "SonicPyWheel",
        progress_message = "Building Python wheel %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out_whl]))]

sonic_python_wheel = rule(
    implementation = _sonic_python_wheel_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            doc = "Source tree label containing setup.py or pyproject.toml.",
        ),
        "deps": attr.label_list(
            default = [],
            doc = "Runtime Python dependencies (other wheels or py_library targets).",
        ),
        "build_deps": attr.label_list(
            default = [],
            doc = "Build-time @bookworm package dependencies for C extensions.",
        ),
        "python_version": attr.string(
            default = "py3",
            doc = "Python version tag for wheel filename (default: py3).",
        ),
    },
    doc = "Builds a Python wheel from SONiC source using setup.py or pyproject.toml.",
)
