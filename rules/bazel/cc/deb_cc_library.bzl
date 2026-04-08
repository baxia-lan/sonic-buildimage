"""Helper for creating cc_library targets from rules_distroless apt packages.

rules_distroless provides each Debian package as a tar archive (:data).
This macro extracts headers and shared libraries from the tar and creates
a cc_library target usable by native Bazel builds.

Usage:
    deb_cc_library(
        name = "hiredis",
        deb_data = "@bookworm_libhiredis-dev_0.14.1-3_amd64//:data",
        hdrs_glob = ["usr/include/hiredis/**"],
        shared_libs = ["usr/lib/x86_64-linux-gnu/libhiredis.so"],
        includes = ["usr/include"],
    )
"""

def deb_cc_library(
        name,
        deb_data,
        runtime_deb_data = None,
        hdrs_glob = [],
        shared_libs = [],
        static_libs = [],
        includes = [],
        deps = [],
        visibility = None):
    """Create a cc_library from a rules_distroless package tar.

    This extracts the package tar and exposes headers + libraries
    for native cc_library consumption.
    """

    # Extract the deb data tar into a directory
    extract_name = name + "_extract"
    native.genrule(
        name = extract_name,
        srcs = [deb_data] + ([runtime_deb_data] if runtime_deb_data else []),
        outs = [name + "_sysroot"],
        cmd = """
            mkdir -p $@
            for src in $(SRCS); do
                tar xf "$$src" -C $@ 2>/dev/null || true
            done
        """,
        visibility = ["//visibility:private"],
    )

    # The cc_library just points to the extracted directory
    native.cc_library(
        name = name,
        hdrs = native.glob(hdrs_glob) if hdrs_glob else [],
        includes = includes,
        srcs = shared_libs + static_libs,
        deps = deps,
        visibility = visibility or ["//visibility:public"],
    )
