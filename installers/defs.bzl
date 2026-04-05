"""Shared macros for SONiC installer migration targets."""

load("//bazel/sonic:defs.bzl", "sonic_host_image")

def sonic_installer_manifest(name, platform, data):
    """Declares only the manifest/lock view for a SONiC installer target."""

    artifact_kwargs = dict(data)
    sonic_host_image(
        name = name,
        fragments = [platform],
        **artifact_kwargs
    )

def sonic_installer_variant(name, platform, data):
    """Declares a SONiC installer target plus a single-file exported lock."""

    artifact_kwargs = dict(data)
    lock_output_name = artifact_kwargs.pop(
        "lock_output_name",
        artifact_kwargs["legacy_artifact"] + ".lock.json",
    )

    sonic_host_image(
        name = name,
        fragments = [platform],
        **artifact_kwargs
    )

    native.genrule(
        name = name + "_lock",
        srcs = [":" + name],
        outs = [lock_output_name],
        cmd = """
lock=''
for f in $(SRCS); do
  case "$$f" in
    *.lock.json)
      lock="$$f"
      ;;
  esac
done
test -n "$$lock"
cp "$$lock" "$@"
""",
        visibility = ["//visibility:public"],
    )
