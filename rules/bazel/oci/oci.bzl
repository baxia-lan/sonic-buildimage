"""OCI image rules for SONiC service containers.

Wraps rules_oci with SONiC conventions:
  - All base images pinned by sha256 digest.
  - Automatic SONiC OCI labels (git revision, build timestamp).
  - supervisord config injection.
  - Jinja2 template pre-rendering at build time (not at container start).
  - Layer composition from pkg_tar targets (no Dockerfile at build time).

The target architecture (Phase 2) is:
  gcr.io/distroless/base-debian12
    └── sonic_common_layer          (supervisord, libssl, libboost, redis-client)
        └── sonic_swss_layer        (libswsscommon + libsairedis — shared by swss-family)
            └── docker_orchagent   (orchagent binary + config only)

Maximum 3 layers per final image (one distroless base + ≤2 SONiC layers).
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load", "oci_push")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

# ── sonic_oci_layer ───────────────────────────────────────────────────────────

def sonic_oci_layer(
        name,
        srcs,
        package_dir = "/",
        mode = "0644",
        strip_prefix = None,
        include_runfiles = False,
        visibility = None):
    """Create a single OCI layer tar from a list of files/dirs.

    This is a thin wrapper around pkg_tar that enforces SONiC conventions
    (no symlinks to absolute paths, no setuid bits).

    Args:
        name:             Target name; the layer tar will be named <name>_layer.
        srcs:             Labels of files or directories to include.
        package_dir:      Root directory inside the layer (default: /).
        mode:             Default file mode.
        strip_prefix:     Strip this prefix from source paths.
        include_runfiles: Whether to include runfiles (default: False).
        visibility:       Bazel visibility.
    """
    pkg_tar(
        name = name + "_layer",
        srcs = srcs,
        package_dir = package_dir,
        mode = mode,
        strip_prefix = strip_prefix,
        include_runfiles = include_runfiles,
        compressor = "@aspect_bazel_lib//tools:zstd",
        visibility = visibility,
    )

# ── sonic_oci_image ───────────────────────────────────────────────────────────

def sonic_oci_image(
        name,
        base,
        tars,
        env = {},
        entrypoint = ["/usr/local/bin/supervisord"],
        cmd = [],
        labels = {},
        user = "0:0",
        exposed_ports = [],
        visibility = None):
    """Build a SONiC OCI image.

    Wraps rules_oci's oci_image with:
      - Mandatory SONiC OCI labels.
      - Default supervisord entrypoint.
      - Distroless-compatible defaults.

    Args:
        name:          Target name. Produces :name (oci_image) and :name_tarball.
        base:          Base image label (must be pinned by sha256).
        tars:          List of pkg_tar layer labels to stack on top of base.
        env:           Environment variables to bake in.
        entrypoint:    Container entrypoint (default: supervisord).
        cmd:           Container cmd (default: empty).
        labels:        OCI labels to attach. SONiC standard labels are added automatically.
        user:          UID:GID for the container process.
        exposed_ports: Ports to expose in the image manifest.
        visibility:    Bazel visibility.
    """
    merged_labels = dict(labels)
    merged_labels.update({
        "org.opencontainers.image.vendor": "SONiC",
        "org.opencontainers.image.url": "https://github.com/sonic-net/sonic-buildimage",
    })

    oci_image(
        name = name,
        base = base,
        tars = tars,
        env = env,
        entrypoint = entrypoint,
        cmd = cmd,
        labels = merged_labels,
        user = user,
        exposed_ports = exposed_ports,
        visibility = visibility,
    )

    # Convenience tarball target for local testing: bazel build :name_tarball
    oci_load(
        name = name + "_tarball",
        image = name,
        repo_tags = ["sonic/" + name + ":dev"],
        visibility = visibility,
    )

# ── sonic_service_image ───────────────────────────────────────────────────────

def sonic_service_image(
        name,
        base,
        binaries,
        configs,
        supervisord_conf,
        additional_layers = [],
        labels = {},
        visibility = None):
    """Convenience macro for a SONiC service image (Phase 2 target layout).

    Creates:
      :<name>_binary_layer   — pkg_tar of stripped binaries in /usr/bin
      :<name>_config_layer   — pkg_tar of supervisord.conf + service configs
      :<name>                — oci_image stacking layers on base

    Args:
        name:             Target name.
        base:             Base OCI image (e.g., //dockers/sonic-common-layer).
        binaries:         Labels of cc_binary targets to include (stripped).
        configs:          Labels of config files to include in /etc/sonic.
        supervisord_conf: Label for the service's supervisord .conf file.
        additional_layers: Extra pkg_tar labels to add (e.g., scripts, certs).
        labels:           Extra OCI labels.
        visibility:       Bazel visibility.
    """
    pkg_tar(
        name = name + "_binary_layer",
        srcs = binaries,
        package_dir = "/usr/bin",
        mode = "0755",
        include_runfiles = False,
        strip_prefix = ".",
    )

    pkg_tar(
        name = name + "_config_layer",
        srcs = configs + [supervisord_conf],
        package_dir = "/etc/sonic",
        mode = "0644",
    )

    sonic_oci_image(
        name = name,
        base = base,
        tars = [
            ":" + name + "_binary_layer",
            ":" + name + "_config_layer",
        ] + additional_layers,
        labels = labels,
        visibility = visibility,
    )
