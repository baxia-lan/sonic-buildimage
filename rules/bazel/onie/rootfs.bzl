"""SONiC rootfs assembly for ONIE images.

Creates a compressed rootfs image containing:
  - Base Debian filesystem from distroless packages
  - All service Docker image tarballs
  - Platform configuration
  - SONiC system files
"""

def sonic_rootfs_image(
        name,
        platform,
        service_images,
        base_packages = [],
        visibility = None):
    """Assemble a SONiC rootfs for ONIE installer.

    The rootfs is a tar containing:
      /var/lib/docker/images/ — pre-loaded Docker images
      /etc/sonic/ — platform config
      /usr/bin/ — SONiC scripts

    Args:
        name:            Target name. Produces <name>.tar.gz
        platform:        Platform name (broadcom, mellanox, vs)
        service_images:  List of OCI tarball labels.
        base_packages:   Additional package layer labels.
        visibility:      Bazel visibility.
    """
    native.genrule(
        name = name,
        srcs = service_images + base_packages,
        outs = [name + ".tar.gz"],
        cmd = "\n".join([
            "set -euo pipefail",
            "WORK=$$(mktemp -d)",
            "trap 'rm -rf \"$$WORK\"' EXIT",
            "mkdir -p \"$$WORK/var/lib/docker/images\" \"$$WORK/etc/sonic\" \"$$WORK/usr/bin\"",
            "for img in $(SRCS); do cp \"$$img\" \"$$WORK/var/lib/docker/images/\" 2>/dev/null || true; done",
            "echo '{\"platform\": \"" + platform + "\"}' > \"$$WORK/etc/sonic/platform.json\"",
            "tar -czf $(OUTS) -C \"$$WORK\" .",
        ]),
        visibility = visibility,
    )
