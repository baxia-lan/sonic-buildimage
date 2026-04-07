"""Run tests for Debian packages built via deb_package_set.

Since the .deb packages are built inside Docker containers, tests also
run inside Docker using the same build environment. This ensures tests
have access to the correct libraries and headers.

Usage:
    deb_test(
        name = "swss_common_test",
        src_dir = "//src/sonic-swss-common",
        build_deps = ["//src/libnl3:libnl3_dev"],
        test_cmd = "make check",
    )
"""

def deb_test(
        name,
        src_dir,
        build_deps = [],
        test_cmd = "make check",
        timeout = "long",
        visibility = None):
    """Run tests for a Debian source package inside Docker.

    Args:
        name:       Test target name.
        src_dir:    Label of the source directory.
        build_deps: List of build dependency .deb labels.
        test_cmd:   Shell command to run tests (default: make check).
        timeout:    Test timeout (short/moderate/long/eternal).
        visibility: Bazel visibility.
    """
    native.sh_test(
        name = name,
        srcs = ["//rules/bazel/test:run_deb_test.sh"],
        data = [src_dir] + build_deps,
        args = [
            "$(location " + src_dir + ")",
            test_cmd,
        ],
        timeout = timeout,
        tags = ["requires-docker", "no-sandbox"],
        visibility = visibility,
    )
