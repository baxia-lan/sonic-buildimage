"""Python wheel building rules for SONiC.

Wraps rules_python's py_wheel with SONiC conventions:
  - Platform wheel tags derived from build platform constraint.
  - VERSION file injection from git tags.
  - Consistent naming: sonic-<pkg>-<version>-py3-none-<arch>.whl
"""

load("@rules_python//python:packaging.bzl", "py_wheel")

# ── sonic_wheel ───────────────────────────────────────────────────────────────

def sonic_wheel(
        name,
        distribution,
        version,
        python_requires = ">=3.11",
        deps = [],
        data = [],
        packages = [],
        entry_points = {},
        install_requires = [],
        extras_require = {},
        description = "",
        homepage = "",
        author = "SONiC",
        author_email = "sonic-dev@example.com",
        classifiers = [],
        visibility = None):
    """Build a Python wheel for a SONiC utility package.

    Args:
        name:           Target name; also the wheel filename prefix.
        distribution:   PyPI distribution name (e.g., 'sonic-utilities').
        version:        Package version string.
        python_requires: Python version constraint.
        deps:           py_library deps.
        data:           Non-Python data files to bundle.
        packages:       Python package directories to include.
        entry_points:   Console scripts and entry points dict.
        install_requires: Runtime dependencies (pip package specs).
        extras_require: Optional dependency groups.
        description:    Short description.
        homepage:       Project URL.
        author:         Author name.
        author_email:   Author email.
        classifiers:    PyPI classifiers.
        visibility:     Bazel visibility.
    """
    py_wheel(
        name = name,
        distribution = distribution,
        version = version,
        python_requires = python_requires,
        deps = deps,
        data = data,
        packages = packages,
        entry_points = entry_points,
        requires = install_requires,
        extra_requires = extras_require,
        summary = description,
        homepage = homepage,
        author = author,
        author_email = author_email,
        classifiers = [
            "Programming Language :: Python :: 3",
            "Operating System :: POSIX :: Linux",
        ] + classifiers,
        python_tag = "py3",
        abi_tag = "none",
        platform_tag = select({
            "//platforms:is_amd64": "linux_x86_64",
            "//platforms:is_arm64": "linux_aarch64",
            "//platforms:is_armhf": "linux_armv7l",
        }),
        visibility = visibility,
    )
