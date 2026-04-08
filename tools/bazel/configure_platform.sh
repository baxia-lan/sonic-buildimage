#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  bazel run //platforms/<platform>:configure
  bazel run //platforms/<platform>:prepare

Options:
  --platform <name>          Platform name, for example 'vs' or 'broadcom'
  --arch <arch>              Configured architecture written to .arch
  --init-workspace           Run Bazel workspace init before configure
  --dpkg-admindir-path <p>   DPKG admin dir to create, defaults to /tmp/sonic-dpkg
EOF
}

platform=""
arch=""
init_workspace=0
dpkg_admindir_path="${SONIC_BAZEL_DPKG_ADMINDIR_PATH:-/tmp/sonic-dpkg}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            platform="$2"
            shift 2
            ;;
        --arch)
            arch="$2"
            shift 2
            ;;
        --init-workspace)
            init_workspace=1
            shift
            ;;
        --dpkg-admindir-path)
            dpkg_admindir_path="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

workspace_root="${BUILD_WORKSPACE_DIRECTORY:-}"
if [[ -z "${workspace_root}" ]]; then
    echo "configure_platform.sh must be run via 'bazel run'" >&2
    exit 1
fi

if [[ -z "${platform}" || -z "${arch}" ]]; then
    usage
    exit 1
fi

cd "${workspace_root}"

if [[ ${init_workspace} -eq 1 ]]; then
    "${workspace_root}/tools/bazel/init_workspace.sh"
fi

checkout_ini="platform/checkout/${platform}.ini"
default_platform_path="platform/${platform}"

if [[ -f "${checkout_ini}" ]]; then
    eval "$(
        python3 - "${checkout_ini}" "${default_platform_path}" <<'PY'
import configparser
import os
import shlex
import sys

checkout_ini = sys.argv[1]
default_platform_path = sys.argv[2]
config = configparser.ConfigParser()
config.read(checkout_ini)
module = config["module"]

path = module.get("path", os.environ.get("PLATFORM_PATH") or default_platform_path)
repo = os.environ.get("PLATFORM_REPO") or module.get("repo", "")
ref = os.environ.get("PLATFORM_REF") or module.get("ref", "")

print("CHECKOUT_PATH=%s" % shlex.quote(path))
print("CHECKOUT_REPO=%s" % shlex.quote(repo))
print("CHECKOUT_REF=%s" % shlex.quote(ref))
PY
    )"

    if [[ ! -d "${CHECKOUT_PATH}" ]]; then
        if [[ -z "${CHECKOUT_REPO}" ]]; then
            echo "Platform checkout config ${checkout_ini} is missing a repo" >&2
            exit 1
        fi
        git clone "${CHECKOUT_REPO}" "${CHECKOUT_PATH}"
    fi

    if [[ ! -d "${CHECKOUT_PATH}/.git" ]]; then
        echo "${CHECKOUT_PATH}/.git not found after checkout" >&2
        exit 1
    fi

    if [[ -n "${CHECKOUT_REF}" ]]; then
        git -C "${CHECKOUT_PATH}" checkout "${CHECKOUT_REF}"
    fi
    git -C "${CHECKOUT_PATH}" submodule update --init --recursive
fi

mkdir -p \
    target/debs/jessie \
    target/debs/stretch \
    target/debs/buster \
    target/debs/bullseye \
    target/debs/bookworm \
    target/debs/trixie \
    target/files/jessie \
    target/files/stretch \
    target/files/buster \
    target/files/bullseye \
    target/files/bookworm \
    target/files/trixie \
    target/phony/bookworm \
    target/phony/trixie \
    target/python-debs/bookworm \
    target/python-debs/trixie \
    target/python-wheels/bookworm \
    target/python-wheels/trixie \
    target/vcache \
    "${dpkg_admindir_path}"

printf '%s\n' "${platform}" > .platform
printf '%s\n' "${arch}" > .arch

echo "Configured SONiC workspace for platform=${platform} arch=${arch}"
echo "  .platform=$(cat .platform)"
echo "  .arch=$(cat .arch)"
