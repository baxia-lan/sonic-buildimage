#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_docker_archive.sh \
    --output <image.tar.gz> \
    --base-image <docker-image> \
    --builder-image <docker-image> \
    --docker-platform <platform> \
    [--repo-tag <repo:tag>] \
    [--env-json '{"KEY":"VALUE"}'] \
    [--entrypoint-json '["/bin/bash"]'] \
    [--cmd-json '["/bin/bash"]'] \
    [--user <name>] \
    [--workdir </path>] \
    [--runtime-deb <artifact.deb>] \
    [--wheel <artifact.whl>] \
    [--file-map <abs-src>=</dest/path>] ...
EOF
}

output=""
base_image=""
builder_image=""
docker_platform="linux/amd64"
env_json="{}"
entrypoint_json=""
cmd_json=""
user_name=""
workdir_path=""
declare -a repo_tags=()
declare -a runtime_debs=()
declare -a wheels=()
declare -a file_maps=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            output="$2"
            shift 2
            ;;
        --base-image)
            base_image="$2"
            shift 2
            ;;
        --builder-image)
            builder_image="$2"
            shift 2
            ;;
        --docker-platform)
            docker_platform="$2"
            shift 2
            ;;
        --repo-tag)
            repo_tags+=("$2")
            shift 2
            ;;
        --env-json)
            env_json="$2"
            shift 2
            ;;
        --entrypoint-json)
            entrypoint_json="$2"
            shift 2
            ;;
        --cmd-json)
            cmd_json="$2"
            shift 2
            ;;
        --user)
            user_name="$2"
            shift 2
            ;;
        --workdir)
            workdir_path="$2"
            shift 2
            ;;
        --runtime-deb)
            runtime_debs+=("$2")
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

if [[ -z "${output}" || -z "${base_image}" || -z "${builder_image}" ]]; then
    usage
    exit 1
fi

if [[ ${#repo_tags[@]} -eq 0 ]]; then
    repo_tags=("sonic-bazel-local:latest")
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

tmpdir="$(mktemp -d)"
rootfs="${tmpdir}/rootfs"
runtime_dir="${tmpdir}/runtime-debs"
wheel_dir="${tmpdir}/wheels"
archive_tar="${tmpdir}/rootfs.tar"
mkdir -p "${rootfs}" "${runtime_dir}" "${wheel_dir}"

cleanup() {
    if [[ -n "${import_tag:-}" ]]; then
        "${docker_bin}" image rm -f "${import_tag}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${container_id:-}" ]]; then
        "${docker_bin}" rm -f "${container_id}" >/dev/null 2>&1 || true
    fi
    rm -rf "${tmpdir}"
}
trap cleanup EXIT

for deb in "${runtime_debs[@]-}"; do
    [[ -n "${deb}" ]] || continue
    cp -p "${deb}" "${runtime_dir}/$(basename "${deb}")"
done

for wheel in "${wheels[@]-}"; do
    [[ -n "${wheel}" ]] || continue
    cp -p "${wheel}" "${wheel_dir}/$(basename "${wheel}")"
done

container_id="$("${docker_bin}" create --platform "${docker_platform}" "${base_image}")"
"${docker_bin}" export "${container_id}" | tar -xf - -C "${rootfs}"
"${docker_bin}" rm "${container_id}" >/dev/null
container_id=""

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
    -v "${tmpdir}:/work" \
    "${builder_image}" \
    bash -lc "
set -euo pipefail

export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
if compgen -G '/work/runtime-debs/*.deb' >/dev/null; then
    for deb in /work/runtime-debs/*.deb; do
        dpkg-deb -x \"\${deb}\" /work/rootfs
    done
fi
if compgen -G '/work/wheels/*.whl' >/dev/null; then
    python3 -m pip install --break-system-packages --no-cache-dir --no-deps --no-compile --root /work/rootfs /work/wheels/*.whl
fi
"

tar \
    --sort=name \
    --mtime='UTC 1970-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -cf "${archive_tar}" \
    -C "${rootfs}" \
    .

import_tag="${repo_tags[0]}"
declare -a import_args=("import")
if [[ "${env_json}" != "{}" ]]; then
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        import_args+=("--change" "ENV ${line}")
    done < <(python3 - "${env_json}" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
for key in sorted(data):
    print(f"{key}={data[key]}")
PY
)
fi
if [[ -n "${user_name}" ]]; then
    import_args+=("--change" "USER ${user_name}")
fi
if [[ -n "${workdir_path}" ]]; then
    import_args+=("--change" "WORKDIR ${workdir_path}")
fi
if [[ -n "${entrypoint_json}" ]]; then
    import_args+=("--change" "ENTRYPOINT ${entrypoint_json}")
fi
if [[ -n "${cmd_json}" ]]; then
    import_args+=("--change" "CMD ${cmd_json}")
fi

"${docker_bin}" "${import_args[@]}" "${archive_tar}" "${import_tag}" >/dev/null

if [[ ${#repo_tags[@]} -gt 1 ]]; then
    for tag in "${repo_tags[@]:1}"; do
        "${docker_bin}" tag "${import_tag}" "${tag}"
    done
fi

"${docker_bin}" save "${repo_tags[@]}" | gzip -n > "${output}"
