"""Hermetic FRR (Free Range Routing) package repository rule.

Downloads FRR .deb packages from deb.frrouting.org during `bazel fetch`.
Each .deb is pinned by sha256 for reproducibility. No network access at
build time -- only during the repository_rule fetch phase.

The resulting repo exposes:
  @frr//:frr              — extracted frr package filesystem tree (tar)
  @frr//:frr_pythontools  — extracted frr-pythontools filesystem tree (tar)
  @frr//:all_debs         — all raw .deb files (for dpkg -i fallback)

Usage in MODULE.bazel:
    frr_debs = use_repo_rule("//rules/bazel/deb:frr_repo.bzl", "frr_deb_repo")
    frr_debs(
        name = "frr",
        packages = {
            "frr": ["<url>", "<sha256>"],
            "frr-pythontools": ["<url>", "<sha256>"],
        },
    )
"""

def _frr_deb_repo_impl(rctx):
    data_tars = {}

    for pkg_name, info in rctx.attr.packages.items():
        url = info[0]
        sha256 = info[1] if len(info) > 1 and info[1] else ""

        deb_filename = pkg_name + ".deb"
        rctx.download(url, output = deb_filename, sha256 = sha256)

        # ar x extracts into repo root: debian-binary, control.tar.*, data.tar.*
        rctx.execute(["ar", "x", deb_filename])

        # Find and extract the data tarball into a per-package rootfs directory
        rootfs_dir = pkg_name + "_rootfs"
        rctx.execute(["mkdir", "-p", rootfs_dir])

        for ext in ["data.tar.xz", "data.tar.zst", "data.tar.gz"]:
            if rctx.path(ext).exists:
                rctx.execute(["tar", "xf", ext, "-C", rootfs_dir])
                data_tars[pkg_name] = rootfs_dir
                rctx.execute(["rm", "-f", ext])
                break

        # Clean up intermediate ar-extracted files (keep the rootfs and raw .deb)
        for leftover in ["debian-binary", "control.tar.xz", "control.tar.gz",
                         "control.tar.zst"]:
            if rctx.path(leftover).exists:
                rctx.execute(["rm", "-f", leftover])

    # Repack each extracted rootfs into a .tar for use as OCI layer input.
    # Use GNU tar for --sort/--mtime/--owner/--group (BSD tar on macOS lacks these).
    tar_bin = "tar"
    gtar_result = rctx.execute(["which", "gtar"])
    if gtar_result.return_code == 0:
        tar_bin = gtar_result.stdout.strip()

    for pkg_name, rootfs_dir in data_tars.items():
        tar_result = rctx.execute([
            tar_bin,
            "--sort=name",
            "--mtime=@0",
            "--owner=0",
            "--group=0",
            "-cf",
            pkg_name + ".tar",
            "-C",
            rootfs_dir,
            ".",
        ])
        if tar_result.return_code != 0:
            fail("Failed to repack {}: {}".format(pkg_name, tar_result.stderr))

    # Generate BUILD.bazel exposing the tars and raw debs
    pkg_names = sorted(data_tars.keys())
    tar_targets = []
    deb_targets = []

    for pkg_name in pkg_names:
        safe_name = pkg_name.replace("-", "_")
        tar_targets.append("""\
filegroup(
    name = "{safe_name}",
    srcs = ["{pkg_name}.tar"],
    visibility = ["//visibility:public"],
)
""".format(safe_name = safe_name, pkg_name = pkg_name))

        deb_targets.append("""\
filegroup(
    name = "{safe_name}_deb",
    srcs = ["{pkg_name}.deb"],
    visibility = ["//visibility:public"],
)
""".format(safe_name = safe_name, pkg_name = pkg_name))

    all_deb_srcs = ", ".join(['"{}.deb"'.format(p) for p in pkg_names])

    build_content = """\
package(default_visibility = ["//visibility:public"])

{tar_targets}
{deb_targets}
filegroup(
    name = "all_debs",
    srcs = [{all_deb_srcs}],
)
""".format(
        tar_targets = "\n".join(tar_targets),
        deb_targets = "\n".join(deb_targets),
        all_deb_srcs = all_deb_srcs,
    )

    rctx.file("BUILD.bazel", build_content)

frr_deb_repo = repository_rule(
    implementation = _frr_deb_repo_impl,
    attrs = {
        "packages": attr.string_list_dict(
            mandatory = True,
            doc = "Dict of {package_name: [url, sha256]} for FRR .deb packages.",
        ),
    },
    doc = "Downloads FRR .deb packages and extracts them for hermetic OCI layer assembly.",
)
