#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_legacy_artifact_bridge.sh \
    --workspace-marker <MODULE.bazel> \
    --version-file <stable-status.txt> \
    --output <artifact-output> \
    --legacy-target <make-target> \
    --artifact-path <relative-path-under-target> \
    --platform <platform> \
    [--bldenv <bookworm>] \
    [--manifest <manifest-json>] \
    [--docker-platform <linux/amd64>] \
    [--make-var KEY=VALUE]...
EOF
}

workspace_marker=""
version_file=""
output=""
legacy_target=""
artifact_path=""
platform=""
bldenv="bookworm"
manifest=""
docker_platform=""
declare -a make_vars=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-marker)
            workspace_marker="$2"
            shift 2
            ;;
        --version-file)
            version_file="$2"
            shift 2
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        --legacy-target)
            legacy_target="$2"
            shift 2
            ;;
        --artifact-path)
            artifact_path="$2"
            shift 2
            ;;
        --platform)
            platform="$2"
            shift 2
            ;;
        --bldenv)
            bldenv="$2"
            shift 2
            ;;
        --manifest)
            manifest="$2"
            shift 2
            ;;
        --docker-platform)
            docker_platform="$2"
            shift 2
            ;;
        --make-var)
            make_vars+=("$2")
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

if [[ -z "${workspace_marker}" || -z "${version_file}" || -z "${output}" || -z "${legacy_target}" || -z "${artifact_path}" || -z "${platform}" ]]; then
    usage
    exit 1
fi

workspace_marker="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${workspace_marker}")"
version_file="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${version_file}")"
workspace_root="$(dirname "${workspace_marker}")"
export HOME="${HOME:-$(dirname "${workspace_root}")}"
export PATH="/Applications/Docker.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
bridge_tmp_root="${SONIC_BAZEL_LEGACY_BRIDGE_TMPDIR_ROOT:-${workspace_root}/.cache/legacy-bridge/tmp-host}"
mkdir -p "${bridge_tmp_root}"
tmpdir="$(mktemp -d "${bridge_tmp_root}/tmp.XXXXXX")"
sanitize_path_component() {
    printf '%s' "$1" | tr '/: ' '---' | tr -cd 'A-Za-z0-9._-'
}

docker_platform_component="default"
if [[ -n "${docker_platform}" ]]; then
    docker_platform_component="$(sanitize_path_component "${docker_platform}")"
fi

artifact_component="$(sanitize_path_component "${artifact_path}")"
if [[ -z "${artifact_component}" ]]; then
    artifact_component="$(sanitize_path_component "${legacy_target}")"
fi

bridge_cache_generation="${SONIC_BAZEL_LEGACY_BRIDGE_CACHE_GEN:-v2}"
saved_platform="${tmpdir}/saved.platform"
saved_arch="${tmpdir}/saved.arch"
restore_platform=0
restore_arch=0
helper_make_vars="${tmpdir}/make_vars.txt"
helper_script="${tmpdir}/run_in_helper.sh"
keep_debug_dirs="${SONIC_BAZEL_LEGACY_BRIDGE_KEEP_WORKDIR:-0}"

source_fingerprint="$(awk '/^STABLE_SONIC_REPO_INPUTS_DIGEST / { print $2; exit }' "${version_file}")"
if [[ -z "${source_fingerprint}" ]]; then
    echo "workspace status file ${version_file} is missing STABLE_SONIC_REPO_INPUTS_DIGEST" >&2
    exit 1
fi
source_fingerprint_component="${source_fingerprint:0:16}"
relative_target_dir=".bazel-legacy-target/bridge-${bridge_cache_generation}-$(sanitize_path_component "${platform}")-${bldenv}-${docker_platform_component}-${artifact_component}-${source_fingerprint_component}"
target_dir="${workspace_root}/${relative_target_dir}"
helper_target_dir="${relative_target_dir}"

resolve_host_tool() {
    local tool="$1"
    local candidate=""

    if candidate="$(command -v "${tool}" 2>/dev/null)"; then
        echo "${candidate}"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/bin/${tool}" \
        "/usr/local/bin/${tool}" \
        "/Applications/Docker.app/Contents/Resources/bin/${tool}"
    do
        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

cleanup() {
    local exit_code=$?

    if [[ ${restore_platform} -eq 1 ]]; then
        mv "${saved_platform}" "${workspace_root}/.platform"
    else
        rm -f "${workspace_root}/.platform"
    fi

    if [[ ${restore_arch} -eq 1 ]]; then
        mv "${saved_arch}" "${workspace_root}/.arch"
    else
        rm -f "${workspace_root}/.arch"
    fi

    if [[ "${keep_debug_dirs}" == "1" || "${keep_debug_dirs}" == "true" || ${exit_code} -ne 0 ]]; then
        echo "Preserving legacy bridge workdirs for debugging:" >&2
        echo "  tmpdir=${tmpdir}" >&2
        echo "  target_dir=${target_dir}" >&2
        return
    fi

    rm -rf "${tmpdir}"
    rm -rf "${target_dir}"
}
trap cleanup EXIT

if [[ -f "${workspace_root}/.platform" ]]; then
    cp "${workspace_root}/.platform" "${saved_platform}"
    restore_platform=1
fi

if [[ -f "${workspace_root}/.arch" ]]; then
    cp "${workspace_root}/.arch" "${saved_arch}"
    restore_arch=1
fi

host_docker="$(resolve_host_tool docker || true)"
if [[ -z "${host_docker}" ]]; then
    echo "docker binary not found on host PATH or standard install locations" >&2
    exit 1
fi

helper_image_ref_script="${workspace_root}/tools/bazel/legacy_bridge_helper_image_ref.sh"
helper_image="${SONIC_BAZEL_LEGACY_BRIDGE_HELPER_IMAGE:-$("${helper_image_ref_script}")}"
if ! "${host_docker}" image inspect "${helper_image}" >/dev/null 2>&1; then
    echo "legacy bridge helper image not found: ${helper_image}" >&2
    echo "build it first with ./tools/bazel/build_legacy_bridge_helper_image.sh" >&2
    exit 1
fi

build_target="${legacy_target}"
if [[ "${legacy_target}" == target/* ]]; then
    build_target="${helper_target_dir}/${legacy_target#target/}"
fi

if [[ -n "${manifest}" ]]; then
    echo "Using manifest ${manifest}" >&2
fi

printf '%s\n' "${make_vars[@]-}" > "${helper_make_vars}"

workspace_uid="${SONIC_BAZEL_LEGACY_BRIDGE_WORKSPACE_UID:-$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_uid)' "${workspace_root}")}"
workspace_gid="${SONIC_BAZEL_LEGACY_BRIDGE_WORKSPACE_GID:-$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_gid)' "${workspace_root}")}"
if [[ "${workspace_uid}" == "0" ]]; then
    workspace_uid="${SONIC_BAZEL_LEGACY_BRIDGE_FALLBACK_UID:-1000}"
fi
if [[ "${workspace_gid}" == "0" ]]; then
    workspace_gid="${SONIC_BAZEL_LEGACY_BRIDGE_FALLBACK_GID:-1000}"
fi
bridge_cache_source="${workspace_root}/.cache/legacy-bridge/artifacts-v2-${bridge_cache_generation}-${source_fingerprint_component}"
mkdir -p "${target_dir}" "${bridge_cache_source}"

cat > "${helper_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if ! command -v j2 >/dev/null 2>&1; then
    echo "required helper tool missing: j2" >&2
    exit 1
fi

if getent group "${BRIDGE_WORKSPACE_GID}" >/dev/null; then
    workspace_group="$(getent group "${BRIDGE_WORKSPACE_GID}" | cut -d: -f1)"
else
    workspace_group="bridgebuilder"
    groupadd -g "${BRIDGE_WORKSPACE_GID}" "${workspace_group}"
fi

if getent passwd "${BRIDGE_WORKSPACE_UID}" >/dev/null; then
    workspace_user="$(getent passwd "${BRIDGE_WORKSPACE_UID}" | cut -d: -f1)"
else
    workspace_user="bridgebuilder"
    useradd -m -u "${BRIDGE_WORKSPACE_UID}" -g "${workspace_group}" -s /bin/bash "${workspace_user}"
fi

echo "${workspace_user} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${workspace_user}"
chmod 0440 "/etc/sudoers.d/${workspace_user}"

socket_gid="$(stat -c '%g' /var/run/docker.sock)"
if getent group "${socket_gid}" >/dev/null; then
    socket_group="$(getent group "${socket_gid}" | cut -d: -f1)"
else
    socket_group="dockerhost"
    groupadd -g "${socket_gid}" "${socket_group}"
fi
usermod -aG "${socket_group}" "${workspace_user}"

chown -R "${BRIDGE_WORKSPACE_UID}:${BRIDGE_WORKSPACE_GID}" /bridge-tmp
chmod +x /bridge-tmp/run_make_in_helper.sh

printf '%s\n' "${BRIDGE_SOURCE_FINGERPRINT}" > "${BRIDGE_TARGET_DIR}/.source-fingerprint"

user_home="$(getent passwd "${workspace_user}" | cut -d: -f6)"
sudo -u "${workspace_user}" env \
    BRIDGE_BLDENV="${BRIDGE_BLDENV}" \
    BRIDGE_BUILD_TARGET="${BRIDGE_BUILD_TARGET}" \
    BRIDGE_CACHE_SOURCE="${BRIDGE_CACHE_SOURCE}" \
    BRIDGE_DOCKER_DEFAULT_PLATFORM="${BRIDGE_DOCKER_DEFAULT_PLATFORM}" \
    BRIDGE_PLATFORM="${BRIDGE_PLATFORM}" \
    BRIDGE_SOURCE_FINGERPRINT="${BRIDGE_SOURCE_FINGERPRINT}" \
    BRIDGE_TARGET_DIR="${BRIDGE_TARGET_DIR}" \
    BRIDGE_WORKSPACE_ROOT="${BRIDGE_WORKSPACE_ROOT}" \
    HOME="${user_home}" \
    /bridge-tmp/run_make_in_helper.sh
EOF

cat > "${tmpdir}/run_make_in_helper.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "${BRIDGE_WORKSPACE_ROOT}"

if [[ -n "${BRIDGE_DOCKER_DEFAULT_PLATFORM:-}" ]]; then
    export DOCKER_DEFAULT_PLATFORM="${BRIDGE_DOCKER_DEFAULT_PLATFORM}"
fi

HOST_DOCKERD_GID="$(stat -c '%g' /var/run/docker.sock)"
MAKE_ARGS=(
    make
    -f
    Makefile.work
    "BLDENV=${BRIDGE_BLDENV}"
    "DEFAULT_CONTAINER_REGISTRY="
    "DPKG_ADMINDIR_PATH=/tmp/sonic-dpkg"
    "MIRROR_SECURITY_URLS=http://deb.debian.org/debian-security"
    "MIRROR_URLS=http://deb.debian.org/debian"
    "PLATFORM=${BRIDGE_PLATFORM}"
    "SONIC_DPKG_ADMINDIR_MODE=copy"
    "SONIC_DPKG_CACHE_SOURCE=${BRIDGE_CACHE_SOURCE}"
    "TARGET_PATH=${BRIDGE_TARGET_DIR}"
    "HOST_DOCKERD_GID=${HOST_DOCKERD_GID}"
)

while IFS= read -r make_var; do
    [[ -n "${make_var}" ]] || continue
    MAKE_ARGS+=("${make_var}")
done < /bridge-tmp/make_vars.txt

"${MAKE_ARGS[@]}" configure
"${MAKE_ARGS[@]}" "${BRIDGE_BUILD_TARGET}"
EOF

chmod +x "${helper_script}" "${tmpdir}/run_make_in_helper.sh"

(
    cd "${workspace_root}"
    "${host_docker}" run --rm \
        -e BRIDGE_BLDENV="${bldenv}" \
        -e BRIDGE_BUILD_TARGET="${build_target}" \
        -e BRIDGE_CACHE_SOURCE="${bridge_cache_source}" \
        -e BRIDGE_DOCKER_DEFAULT_PLATFORM="${docker_platform}" \
        -e BRIDGE_PLATFORM="${platform}" \
        -e BRIDGE_SOURCE_FINGERPRINT="${source_fingerprint}" \
        -e BRIDGE_TARGET_DIR="${helper_target_dir}" \
        -e BRIDGE_WORKSPACE_UID="${workspace_uid}" \
        -e BRIDGE_WORKSPACE_GID="${workspace_gid}" \
        -e BRIDGE_WORKSPACE_ROOT="${workspace_root}" \
        -v "${workspace_root}:${workspace_root}" \
        -v "${tmpdir}:/bridge-tmp" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -w "${workspace_root}" \
        "${helper_image}" \
        /bridge-tmp/run_in_helper.sh
)

artifact_source="${target_dir}/${artifact_path}"
if [[ ! -f "${artifact_source}" ]]; then
    echo "Legacy bridge did not produce ${artifact_source}" >&2
    exit 1
fi

cp "${artifact_source}" "${output}"
