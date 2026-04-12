"""Hermetic runtime dependency repo rule — downloads .deb packages at fetch time.

Downloads specific .deb packages from snapshot.debian.org during `bazel fetch`,
extracts their contents, and repacks as a tar for use as OCI layers.

No network access during build actions. All downloads happen in this
repository_rule (fetch phase only).

Usage in MODULE.bazel:
    _runtime_deps = use_repo_rule("//rules/bazel/deb:runtime_deps_repo.bzl", "runtime_deps_repo")
    _runtime_deps(
        name = "frr_runtime_deps",
        packages = {
            "libjson-c5": ["https://snapshot.debian.org/.../libjson-c5_0.16-2_amd64.deb", "<sha256>"],
            "libc-ares2": ["https://snapshot.debian.org/.../libc-ares2_1.18.1-3_amd64.deb", "<sha256>"],
        },
    )
"""

def _runtime_deps_repo_impl(rctx):
    rootfs_dir = "rootfs"
    rctx.execute(["mkdir", "-p", rootfs_dir])

    for pkg_name, info in rctx.attr.packages.items():
        url = info[0]
        sha256 = info[1] if len(info) > 1 and info[1] else ""

        deb_path = pkg_name + ".deb"
        rctx.download(url, output = deb_path, sha256 = sha256 if sha256 else "")

        # Extract .deb: ar x → data.tar.* → extract to rootfs
        rctx.execute(["ar", "x", deb_path])
        for ext in ["data.tar.xz", "data.tar.zst", "data.tar.gz"]:
            if rctx.path(ext).exists:
                rctx.execute(["tar", "xf", ext, "-C", rootfs_dir])
                rctx.execute(["rm", "-f", ext])
                break
        rctx.execute(["rm", "-f", deb_path, "debian-binary",
                       "control.tar.xz", "control.tar.gz", "control.tar.zst"])

    # Fix usrmerge: Debian bookworm packages may ship files in bin/, sbin/,
    # lib/ instead of usr/bin/, etc. Move them to avoid shadowing the base
    # image's /bin -> /usr/bin symlinks in OCI layers.
    for d in ["bin", "sbin", "lib"]:
        src = rootfs_dir + "/" + d
        dst = rootfs_dir + "/usr/" + d
        result = rctx.execute(["test", "-d", src])
        if result.return_code == 0:
            link_result = rctx.execute(["test", "-L", src])
            if link_result.return_code != 0:
                rctx.execute(["mkdir", "-p", dst])
                rctx.execute(["sh", "-c", "cp -a " + src + "/. " + dst + "/"])
                rctx.execute(["rm", "-rf", src])

    # Repack into a single tar for OCI layer use
    tar_bin = "tar"
    for candidate in ["/opt/homebrew/bin/gtar", "/usr/local/bin/gtar", "gtar"]:
        result = rctx.execute(["which", candidate])
        if result.return_code == 0:
            tar_bin = result.stdout.strip()
            break

    tar_args = [tar_bin, "-cf", "layer.tar", "-C", rootfs_dir, "."]
    sort_result = rctx.execute([tar_bin, "--sort=name", "--help"])
    if sort_result.return_code == 0:
        tar_args = [tar_bin, "--sort=name", "--mtime=@0", "--owner=0", "--group=0",
                    "-cf", "layer.tar", "-C", rootfs_dir, "."]
    tar_result = rctx.execute(tar_args, environment = {"SOURCE_DATE_EPOCH": "0"})
    if tar_result.return_code != 0:
        fail("Failed to create layer tar: " + tar_result.stderr)

    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "layer",
    srcs = ["layer.tar"],
)
""")

runtime_deps_repo = repository_rule(
    implementation = _runtime_deps_repo_impl,
    attrs = {
        "packages": attr.string_list_dict(
            mandatory = True,
            doc = "Dict of {package_name: [url, sha256]} for runtime .deb packages.",
        ),
    },
    doc = "Downloads runtime .deb packages at fetch time (hermetic — no build-time network).",
)
