"""Top-level SONiC image target with platform selection.

Usage:
  # Broadcom platform (default)
  bazel build //:sonic_image --platforms=//platforms:broadcom_amd64

  # Virtual Switch (for testing)
  bazel build //:sonic_image --platforms=//platforms:vs_amd64

  # Mellanox platform
  bazel build //:sonic_image --platforms=//platforms:mellanox_amd64
"""

def sonic_platform_image(name, visibility = None):
    """Select the correct platform image based on --platforms flag."""
    native.alias(
        name = name,
        actual = select({
            "//platforms:is_broadcom": "//platform/broadcom:sonic_broadcom_bin",
            "//platforms:is_vs": "//platform/vs:sonic_vs_bin",
            "//platforms:is_mellanox": "//platform/mellanox:sonic_mellanox_bin",
            "//conditions:default": "//platform/vs:sonic_vs_bin",
        }),
        visibility = visibility,
    )

def sonic_platform_docker(name, visibility = None):
    """Select the docker-orchagent image with correct SAI for the platform."""
    native.alias(
        name = name,
        actual = "//dockers/docker-orchagent:docker_orchagent",
        visibility = visibility,
    )
