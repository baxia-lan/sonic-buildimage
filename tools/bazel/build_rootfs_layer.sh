#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_rootfs_layer.sh \
    --output <layer.tar> \
    [--docker-image <image>] \
    [--docker-platform <platform>] \
    [--runtime-deb <artifact.deb>] \
    [--runtime-layer <artifact-layer.tar.gz>] \
    [--wheel <artifact.whl>] \
    [--file-map <abs-src>=</dest/path>] ...
EOF
}

output=""
docker_image=""
docker_platform="linux/amd64"
declare -a runtime_debs=()
declare -a runtime_layers=()
declare -a wheels=()
declare -a file_maps=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            output="$2"
            shift 2
            ;;
        --docker-image)
            docker_image="$2"
            shift 2
            ;;
        --docker-platform)
            docker_platform="$2"
            shift 2
            ;;
        --runtime-deb)
            runtime_debs+=("$2")
            shift 2
            ;;
        --runtime-layer)
            runtime_layers+=("$2")
            shift 2
            ;;
        --wheel)
            wheels+=("$2")
            shift 2
            ;;
        --file-map)
            file_maps+=("$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${output}" ]]; then
    usage
    exit 1
fi

docker_bin="${DOCKER_BIN:-docker}"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

configure_docker_host() {
    if [[ -n "${DOCKER_HOST:-}" || -n "${DOCKER_CONTEXT:-}" ]]; then
        return
    fi

    if "${docker_bin}" info >/dev/null 2>&1; then
        return
    fi

    local default_socket="/var/run/docker.sock"
    if [[ -S "${default_socket}" ]] && DOCKER_HOST="unix://${default_socket}" "${docker_bin}" info >/dev/null 2>&1; then
        export DOCKER_HOST="unix://${default_socket}"
        return
    fi

    local user_home="${HOME:-}"
    if [[ -z "${user_home}" ]]; then
        user_home="$(eval echo "~$(id -un)")"
    fi

    local desktop_socket="${user_home}/.docker/run/docker.sock"
    if [[ -S "${desktop_socket}" ]] && DOCKER_HOST="unix://${desktop_socket}" "${docker_bin}" info >/dev/null 2>&1; then
        export DOCKER_HOST="unix://${desktop_socket}"
    fi
}

configure_docker_host

helper_image_ref_script="tools/bazel/legacy_bridge_helper_image_ref.sh"
helper_image_stable_ref="sonic-bazel-legacy-bridge-helper:bookworm"
if [[ ! -x "${helper_image_ref_script}" ]]; then
    workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    helper_image_ref_script="${workspace_root}/tools/bazel/legacy_bridge_helper_image_ref.sh"
fi
if [[ -z "${docker_image}" ]]; then
    docker_image="$("${helper_image_ref_script}")"
fi

inspect_output="$({ "${docker_bin}" image inspect "${docker_image}" >/dev/null; } 2>&1)" || inspect_status=$?
inspect_status="${inspect_status:-0}"
if [[ "${inspect_status}" -ne 0 ]]; then
    stable_inspect_output="$({ "${docker_bin}" image inspect "${helper_image_stable_ref}" >/dev/null; } 2>&1)" || stable_inspect_status=$?
    stable_inspect_status="${stable_inspect_status:-0}"
    if [[ "${docker_image}" != "${helper_image_stable_ref}" ]] && [[ "${stable_inspect_status}" -eq 0 ]]; then
        docker_image="${helper_image_stable_ref}"
    elif grep -Eqi 'permission denied|cannot connect|docker daemon|error during connect' <<<"${inspect_output}${stable_inspect_output}"; then
        echo "Docker helper image lookup failed because the Docker daemon is not reachable from this Bazel action." >&2
        echo "DOCKER_HOST=${DOCKER_HOST:-<unset>}" >&2
        [[ -n "${inspect_output}" ]] && echo "${inspect_output}" >&2
        [[ -n "${stable_inspect_output}" ]] && echo "${stable_inspect_output}" >&2
        exit 1
    else
        echo "Missing local helper image ${docker_image}; build it with tools/bazel/build_legacy_bridge_helper_image.sh before running Bazel rootfs layer builders." >&2
        [[ -n "${inspect_output}" ]] && echo "${inspect_output}" >&2
        exit 1
    fi
fi

workdir="$(mktemp -d)"
rootfs="${workdir}/rootfs"
runtime_dir="${workdir}/runtime-debs"
runtime_layer_dir="${workdir}/runtime-layers"
wheel_dir="${workdir}/wheels"
mkdir -p "${rootfs}" "${runtime_dir}" "${runtime_layer_dir}" "${wheel_dir}"

cleanup() {
    if [[ "${SONIC_BAZEL_KEEP_WORKDIR:-0}" == "1" ]]; then
        echo "Keeping workdir: ${workdir}" >&2
        return
    fi

    rm -rf "${workdir}"
}
trap cleanup EXIT

for deb in "${runtime_debs[@]-}"; do
    [[ -n "${deb}" ]] || continue
    cp -p "${deb}" "${runtime_dir}/$(basename "${deb}")"
done

for layer in "${runtime_layers[@]-}"; do
    [[ -n "${layer}" ]] || continue
    cp -p "${layer}" "${runtime_layer_dir}/$(basename "${layer}")"
done

for wheel in "${wheels[@]-}"; do
    [[ -n "${wheel}" ]] || continue
    cp -p "${wheel}" "${wheel_dir}/$(basename "${wheel}")"
done

for mapping in "${file_maps[@]-}"; do
    [[ -n "${mapping}" ]] || continue
    src="${mapping%%=*}"
    dest="${mapping#*=}"
    if [[ -z "${src}" || -z "${dest}" || "${src}" == "${dest}" ]]; then
        echo "Invalid --file-map: ${mapping}" >&2
        exit 1
    fi
    mkdir -p "${rootfs}/$(dirname "${dest}")"
    cp -p "${src}" "${rootfs}/${dest}"
done

"${docker_bin}" run --rm \
    --pull never \
    --network none \
    --platform "${docker_platform}" \
    -e HOME="/tmp" \
    -e SOURCE_DATE_EPOCH="0" \
    -v "${workdir}:/work" \
    "${docker_image}" \
    bash -lc "
set -euo pipefail

export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

if compgen -G '/work/runtime-debs/*.deb' >/dev/null; then
    for deb in /work/runtime-debs/*.deb; do
        dpkg-deb -x \"\${deb}\" /work/rootfs
    done
fi

if compgen -G '/work/runtime-layers/*' >/dev/null; then
    for layer in /work/runtime-layers/*; do
        case \"\${layer}\" in
            *.tar)
                tar -xf \"\${layer}\" -C /work/rootfs
                ;;
            *.tar.gz|*.tgz)
                tar -xzf \"\${layer}\" -C /work/rootfs
                ;;
            *)
                echo \"Unsupported runtime layer format: \${layer}\" >&2
                exit 1
                ;;
        esac
    done
fi

if compgen -G '/work/wheels/*.whl' >/dev/null; then
    python3 -m pip install --break-system-packages --no-cache-dir --no-deps --no-compile --root /work/rootfs /work/wheels/*.whl
fi

tar \
    --sort=name \
    --mtime='UTC 1970-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -cf /work/layer.tar \
    -C /work/rootfs \
    .
"

install "${workdir}/layer.tar" "${output}"
