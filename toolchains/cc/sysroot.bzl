"""Hermetic Debian sysroot via repository rule (Aspect Build pattern).

Downloads and extracts .deb packages during `bazel fetch` into a source
directory. toolchains_llvm uses this as a sysroot label. No gawk cycle.
"""

def _impl(rctx):
    # Extract directly into repo root so --sysroot=external/repo/ works
    sysroot_dir = "."

    for name, info in rctx.attr.packages.items():
        url = info[0]
        sha256 = info[1] if len(info) > 1 and info[1] else ""

        deb_path = name + ".deb"
        rctx.download(url, output = deb_path, sha256 = sha256 if sha256 else "")

        rctx.execute(["ar", "x", deb_path])

        for ext in ["data.tar.xz", "data.tar.zst", "data.tar.gz"]:
            if rctx.path(ext).exists:
                rctx.execute(["tar", "xf", ext, "-C", sysroot_dir])
                rctx.execute(["rm", "-f", ext])
                break

        rctx.execute(["rm", "-f", deb_path, "debian-binary",
                       "control.tar.xz", "control.tar.gz", "control.tar.zst"])

    # Remove dangling symlinks (cross-package references)
    rctx.execute(["find", sysroot_dir, "-type", "l",
                   "!", "-exec", "test", "-e", "{}", ";", "-delete"])

    # Fix linker scripts with absolute paths → relative to sysroot root.
    # e.g., /lib/x86_64-linux-gnu/libm.so.6 → ../../../lib/x86_64-linux-gnu/libm.so.6
    rctx.execute(["bash", "-c", """
        for f in usr/lib/x86_64-linux-gnu/*.so usr/lib/x86_64-linux-gnu/*.a lib/x86_64-linux-gnu/*.so; do
            [ -f "$f" ] || continue
            if head -1 "$f" 2>/dev/null | grep -qE '^(/\\*|GROUP|INPUT|OUTPUT)'; then
                sed -i 's| /lib/| ../../../lib/|g; s| /usr/lib/| ../../../usr/lib/|g' "$f"
            fi
        done
    """])

    # Standard sysroot dirs
    rctx.execute(["mkdir", "-p", "usr/include", "usr/lib/x86_64-linux-gnu", "lib/x86_64-linux-gnu"])

    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "sysroot",
    srcs = glob(["usr/**", "lib/**", "lib64/**"], allow_empty = True),
)
""")

debian_sysroot_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "packages": attr.string_list_dict(mandatory = True,
            doc = "Dict of {name: [url, sha256]} for sysroot .deb packages."),
    },
    doc = "Downloads Debian .deb packages and extracts into a sysroot during fetch.",
)
