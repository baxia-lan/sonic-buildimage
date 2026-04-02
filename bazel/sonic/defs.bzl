"""Public Bazel APIs for SONiC artifacts."""

load("//bazel/sonic/private:artifacts.bzl", _sonic_deb_package = "sonic_deb_package", _sonic_go_binary = "sonic_go_binary", _sonic_host_image = "sonic_host_image", _sonic_oci_image = "sonic_oci_image", _sonic_platform = "sonic_platform", _sonic_py_wheel = "sonic_py_wheel")
load("//bazel/sonic/private:export.bzl", _sonic_export_to_target_tree = "sonic_export_to_target_tree")

sonic_deb_package = _sonic_deb_package
sonic_py_wheel = _sonic_py_wheel
sonic_go_binary = _sonic_go_binary
sonic_oci_image = _sonic_oci_image
sonic_host_image = _sonic_host_image
sonic_platform = _sonic_platform
sonic_export_to_target_tree = _sonic_export_to_target_tree
