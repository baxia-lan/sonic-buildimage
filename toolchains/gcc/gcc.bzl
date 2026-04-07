"""Hermetic GCC toolchain fetch rule.

Downloads a pre-built GCC distribution, removes the bundled sysroot
(replaced by Debian packages via rules_distroless), and creates
wrapper scripts for the compiler binaries.
"""

_GCC_BUILD = """
load("@bazel_skylib//rules:directory.bzl", "directory")

package(default_visibility = ["//visibility:public"])

directory(
    name = "toolchain_root",
    srcs = glob(["lib/**", "include/**"]),
)

directory(
    name = "builtin_headers",
    srcs = glob(["lib/gcc/x86_64-linux/12.5.0/include/**"]),
)

filegroup(
    name = "linker_builtins",
    srcs = glob([
        "lib/gcc/x86_64-linux/12.5.0/**/*.a",
        "lib/gcc/x86_64-linux/12.5.0/**/*.so*",
        "lib/gcc/x86_64-linux/12.5.0/**/*.o",
        "libexec/gcc/x86_64-linux/12.5.0/ld*",
        "x86_64-linux/bin/ld*",
    ]),
)

filegroup(
    name = "all_files",
    srcs = glob(["**/*"]),
)

exports_files(glob(["bin/*"]))
"""

def _fetch_gcc_impl(rctx):
    rctx.download_and_extract(
        url = rctx.attr.urls,
        integrity = rctx.attr.integrity,
    )

    # Delete bundled sysroot — we use Debian packages instead
    rctx.delete("sysroot")

    # Write BUILD file
    rctx.file("BUILD.bazel", _GCC_BUILD)

fetch_gcc = repository_rule(
    implementation = _fetch_gcc_impl,
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "integrity": attr.string(mandatory = True),
    },
)
