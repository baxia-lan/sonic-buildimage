#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_wheel_package.sh \
    --output <artifact.whl> \
    --docker-image <image> \
    --docker-platform <platform> \
    --source-root <repo/source/root> \
    --package-name <name> \
    --version <version> \
    [--dependency-wheel <wheel>] \
    --src-map <abs-src>=<rel-path> ...
EOF
}

output=""
docker_image=""
docker_platform="linux/amd64"
source_root=""
package_name=""
package_version=""
declare -a dependency_wheels=()
declare -a src_maps=()

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
        --source-root)
            source_root="$2"
            shift 2
            ;;
        --package-name)
            package_name="$2"
            shift 2
            ;;
        --version)
            package_version="$2"
            shift 2
            ;;
        --dependency-wheel)
            dependency_wheels+=("$2")
            shift 2
            ;;
        --src-map)
            src_maps+=("$2")
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

if [[ -z "${output}" || -z "${docker_image}" || -z "${source_root}" || -z "${package_name}" || -z "${package_version}" || ${#src_maps[@]} -eq 0 ]]; then
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

workdir="$(mktemp -d)"
stage_dir="${workdir}/src"
deps_dir="${workdir}/wheel-deps"
out_dir="${workdir}/out"
mkdir -p "${stage_dir}" "${deps_dir}" "${out_dir}"

cleanup() {
    if [[ "${SONIC_BAZEL_KEEP_WORKDIR:-0}" == "1" ]]; then
        echo "Keeping workdir: ${workdir}" >&2
        return
    fi

    rm -rf "${workdir}"
}
trap cleanup EXIT

for mapping in "${src_maps[@]}"; do
    src="${mapping%%=*}"
    rel="${mapping#*=}"
    if [[ -z "${src}" || -z "${rel}" || "${src}" == "${rel}" ]]; then
        echo "Invalid --src-map: ${mapping}" >&2
        exit 1
    fi
    mkdir -p "${stage_dir}/$(dirname "${rel}")"
    cp -p "${src}" "${stage_dir}/${rel}"
done

for wheel in "${dependency_wheels[@]-}"; do
    [[ -n "${wheel}" ]] || continue
    cp -p "${wheel}" "${deps_dir}/$(basename "${wheel}")"
done

"${docker_bin}" run --rm \
    --pull never \
    --network none \
    --platform "${docker_platform}" \
    -e HOME="/tmp" \
    -e PACKAGE_NAME="${package_name}" \
    -e PACKAGE_VERSION="${package_version}" \
    -e SOURCE_DATE_EPOCH="0" \
    -v "${workdir}:/work" \
    "${docker_image}" \
    bash -lc "
set -euo pipefail

export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
cd /work/src

if compgen -G '/work/wheel-deps/*.whl' >/dev/null; then
    python3 -m pip install --break-system-packages --no-cache-dir --no-deps /work/wheel-deps/*.whl
fi

python3 setup.py bdist_wheel --dist-dir /work/out

shopt -s nullglob
matches=(/work/out/*.whl)
if [[ \${#matches[@]} -ne 1 ]]; then
    echo 'Expected exactly one wheel artifact, found' \${#matches[@]} >&2
    printf '%s\n' \"\${matches[@]}\" >&2
    exit 1
fi

cp \"\${matches[0]}\" /work/out/${package_name}-${package_version}.whl
"

install "${out_dir}/${package_name}-${package_version}.whl" "${output}"
