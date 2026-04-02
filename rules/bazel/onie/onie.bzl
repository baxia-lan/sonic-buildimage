"""ONIE installer image rules for SONiC.

Produces a self-extracting ONIE installer (.bin) from:
  - A Linux kernel image + initrd
  - A squashfs rootfs containing all service container tarballs
  - Platform-specific SAI + kernel modules
  - An ONIE installer shell script header

The generated .bin must fit within the 400 MB size budget defined in CLAUDE.md.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

# ── onie_image ────────────────────────────────────────────────────────────────

def _onie_image_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.name + ".bin")

    rootfs_tar = ctx.file.rootfs
    kernel = ctx.file.kernel
    platform_modules = ctx.files.platform_modules
    installer_script = ctx.file.installer_script

    args = ctx.actions.args()
    args.add("--output", output)
    args.add("--kernel", kernel)
    args.add("--rootfs", rootfs_tar)
    args.add("--platform", ctx.attr.platform)
    args.add("--machine", ctx.attr.machine)
    args.add("--version", ctx.attr.version)
    for m in platform_modules:
        args.add("--module", m)

    ctx.actions.run(
        inputs = [rootfs_tar, kernel, installer_script] + platform_modules,
        outputs = [output],
        executable = ctx.executable._onie_builder,
        arguments = [args],
        env = {
            "SOURCE_DATE_EPOCH": "0",
        },
        mnemonic = "OnieImage",
        progress_message = "Building ONIE image %s for %s" % (ctx.attr.name, ctx.attr.platform),
        execution_requirements = {
            "no-remote": "0",
        },
    )

    return [DefaultInfo(files = depset([output]))]

onie_image = rule(
    implementation = _onie_image_impl,
    attrs = {
        "rootfs": attr.label(
            allow_single_file = [".tar", ".tar.gz", ".squashfs"],
            mandatory = True,
            doc = "Root filesystem archive containing all service container tarballs.",
        ),
        "kernel": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Linux kernel vmlinuz image.",
        ),
        "platform_modules": attr.label_list(
            allow_files = True,
            doc = "Platform-specific kernel module .ko files.",
        ),
        "installer_script": attr.label(
            allow_single_file = [".sh"],
            default = "//installer:install.sh",
            doc = "ONIE installer shell script header.",
        ),
        "platform": attr.string(
            mandatory = True,
            doc = "Platform name, e.g. 'broadcom', 'mellanox', 'vs'.",
        ),
        "machine": attr.string(
            mandatory = True,
            doc = "ONIE machine type string.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "SONiC image version string.",
        ),
        "_onie_builder": attr.label(
            default = "//scripts:onie_image_builder",
            executable = True,
            cfg = "exec",
            doc = "ONIE image builder tool.",
        ),
    },
)

# ── sonic_rootfs ──────────────────────────────────────────────────────────────

def sonic_rootfs(
        name,
        platform,
        service_images,
        platform_packages = [],
        base_packages = [],
        visibility = None):
    """Assemble the SONiC rootfs squashfs from service OCI tarballs.

    This target produces the rootfs.tar that is embedded in the ONIE installer.

    Args:
        name:              Target name.
        platform:          Platform name for platform-specific includes.
        service_images:    List of oci_tarball labels (one per SONiC service).
        platform_packages: Platform-specific .deb packages to pre-install.
        base_packages:     Common packages to pre-install in all rootfs images.
        visibility:        Bazel visibility.
    """
    pkg_tar(
        name = name,
        srcs = service_images + platform_packages + base_packages,
        package_dir = "/",
        visibility = visibility,
    )
