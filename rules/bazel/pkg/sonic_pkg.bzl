"""SONiC package assembly rules — native binaries to OCI layer tars.

Replaces Docker genrule dpkg-buildpackage with hermetic tar+mtree packaging.
Based on Aspect/thesayyn pattern: cc_binary → tar(mtree) → flatten → oci_image.

Usage:
    sonic_binary_layer(
        name = "swsscommon_layer",
        binaries = {
            "/usr/lib/x86_64-linux-gnu/libswsscommon.so": "//src/sonic-swss-common:libswsscommon_so",
            "/usr/bin/sonic-db-cli": "//src/sonic-swss-common:sonic_db_cli",
            "/usr/bin/swssloglevel": "//src/sonic-swss-common:swssloglevel",
        },
        data = {
            "/var/run/redis/sonic-db/database_config.json": "//src/sonic-swss-common:common/database_config.json",
        },
    )
"""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def sonic_binary_layer(
        name,
        binaries = {},
        data = {},
        scripts = {},
        visibility = None):
    """Create an OCI layer tar from native Bazel binaries.

    Packages cc_binary outputs into a tar with correct filesystem paths.
    No Docker, no dpkg-buildpackage, fully hermetic.

    Args:
        name:      Target name. Produces <name>.tar
        binaries:  Dict of {container_path: label} for ELF binaries (mode 0755).
        data:      Dict of {container_path: label} for data files (mode 0644).
        scripts:   Dict of {container_path: label} for scripts (mode 0755).
        visibility: Bazel visibility.
    """
    _tars = []
    idx = 0

    for dest_path, src_label in binaries.items():
        idx += 1
        tar_name = name + "_bin_%d" % idx
        pkg_tar(
            name = tar_name,
            srcs = [src_label],
            package_dir = "/".join(dest_path.split("/")[:-1]),
            mode = "0755",
        )
        _tars.append(tar_name)

    for dest_path, src_label in data.items():
        idx += 1
        tar_name = name + "_data_%d" % idx
        pkg_tar(
            name = tar_name,
            srcs = [src_label],
            package_dir = "/".join(dest_path.split("/")[:-1]),
            mode = "0644",
        )
        _tars.append(tar_name)

    for dest_path, src_label in scripts.items():
        idx += 1
        tar_name = name + "_script_%d" % idx
        pkg_tar(
            name = tar_name,
            srcs = [src_label],
            package_dir = "/".join(dest_path.split("/")[:-1]),
            mode = "0755",
        )
        _tars.append(tar_name)

    # Merge all sub-tars
    pkg_tar(
        name = name,
        deps = [":" + t for t in _tars],
        visibility = visibility,
    )
