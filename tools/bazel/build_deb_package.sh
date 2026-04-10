#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_deb_package.sh \
    --output <artifact.deb> \
    [--docker-image <image>] \
    --docker-platform <platform> \
    --source-root <repo/source/root> \
    --deb-pattern <pattern> \
    --package-name <name> \
    --version <version> \
    --arch <arch> \
    [--build-profile <name>] \
    --src-map <abs-src>=<rel-path> ...
EOF
}

output=""
docker_image=""
docker_platform="linux/amd64"
source_root=""
deb_pattern=""
package_name=""
package_version=""
package_arch="amd64"
declare -a build_debs=()
declare -a build_profiles=()
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
        --deb-pattern)
            deb_pattern="$2"
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
        --arch)
            package_arch="$2"
            shift 2
            ;;
        --build-profile)
            build_profiles+=("$2")
            shift 2
            ;;
        --build-deb)
            build_debs+=("$2")
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

if [[ -z "${output}" || -z "${source_root}" || -z "${deb_pattern}" || -z "${package_name}" || -z "${package_version}" || ${#src_maps[@]} -eq 0 ]]; then
    usage
    exit 1
fi

docker_bin="${DOCKER_BIN:-docker}"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

resolve_docker_bin() {
    if [[ "${docker_bin}" == */* ]]; then
        return
    fi

    local candidate
    for candidate in \
        "${DOCKER_BIN:-}" \
        "$(command -v docker 2>/dev/null || true)" \
        "/Applications/Docker.app/Contents/Resources/bin/docker"
    do
        if [[ -n "${candidate}" && -x "${candidate}" ]]; then
            docker_bin="${candidate}"
            return
        fi
    done
}

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

resolve_docker_bin
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
        if [[ -n "${inspect_output}" ]]; then
            echo "${inspect_output}" >&2
        fi
        if [[ -n "${stable_inspect_output}" ]]; then
            echo "${stable_inspect_output}" >&2
        fi
        exit 1
    else
        echo "Missing local helper image ${docker_image}; build it with tools/bazel/build_legacy_bridge_helper_image.sh before running Bazel concrete Debian builders." >&2
        if [[ -n "${inspect_output}" ]]; then
            echo "${inspect_output}" >&2
        fi
        exit 1
    fi
fi
workdir="$(mktemp -d)"
stage_dir="${workdir}/src"
out_dir="${workdir}/out"
deps_dir="${workdir}/build-debs"
wheel_deps_dir="${workdir}/wheel-deps"
python_wheels_dir="${workdir}/python-wheels"
build_dep_count=0
if [[ "${build_debs+set}" == "set" ]]; then
    build_dep_count="${#build_debs[@]}"
fi
wheel_dep_count=0
if [[ "${dependency_wheels+set}" == "set" ]]; then
    wheel_dep_count="${#dependency_wheels[@]}"
fi
mkdir -p "${stage_dir}" "${out_dir}"
if (( build_dep_count > 0 )); then
    mkdir -p "${deps_dir}"
fi
if (( wheel_dep_count > 0 )); then
    mkdir -p "${wheel_deps_dir}" "${python_wheels_dir}"
fi

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

normalize_autotools_timestamps() {
    local source_stamp="200001010000"
    local generated_stamp="200001010100"

    find "${stage_dir}" -type f \( -name "configure.ac" -o -name "aclocal.m4" -o -name "Makefile.am" -o -name "*.m4" \) \
        -exec touch -t "${source_stamp}" {} +

    find "${stage_dir}" -type f \( -name "configure" -o -name "Makefile.in" \) \
        -exec touch -t "${generated_stamp}" {} +
}

normalize_autotools_timestamps

for dep in "${build_debs[@]-}"; do
    [[ -n "${dep}" ]] || continue
    cp -p "${dep}" "${deps_dir}/$(basename "${dep}")"
done

for wheel in "${dependency_wheels[@]-}"; do
    [[ -n "${wheel}" ]] || continue
    cp -p "${wheel}" "${wheel_deps_dir}/$(basename "${wheel}")"
done

rust_build_invoked=0
if [[ -f "${stage_dir}/debian/rules" ]] && grep -Eq '(^|[^[:alnum:]_])cargo[[:space:]]+(build|check|install|run|rustc|test)\b' "${stage_dir}/debian/rules"; then
    rust_build_invoked=1
fi

if [[ "${rust_build_invoked}" -eq 1 ]]; then
    cargo_config_present=0
    if find "${stage_dir}" \( -path '*/.cargo/config.toml' -o -path '*/.cargo/config' \) -type f -print -quit | grep -q .; then
        cargo_config_present=1
    fi

    if [[ ! -f "${stage_dir}/Cargo.lock" ]]; then
        echo "Rust-backed Debian builds must vendor dependencies for Bazel execution: missing ${source_root}/Cargo.lock" >&2
        exit 1
    fi

    if ! find "${stage_dir}" -type d -name vendor -print -quit | grep -q .; then
        echo "Rust-backed Debian builds must vendor crates for Bazel execution: missing vendor/ tree under ${source_root}" >&2
        exit 1
    fi

    if [[ "${cargo_config_present}" -ne 1 ]]; then
        echo "Rust-backed Debian builds must provide .cargo/config.toml or .cargo/config pointing Cargo at vendored crates under ${source_root}" >&2
        exit 1
    fi
fi

build_profile_args=""
if (( ${#build_profiles[@]} > 0 )); then
    build_profile_args="-P$(IFS=,; echo "${build_profiles[*]}")"
fi

"${docker_bin}" run --rm \
    --pull never \
    --network none \
    --platform "${docker_platform}" \
    -e CARGO_NET_OFFLINE="true" \
    -e DEB_BUILD_OPTIONS="nocheck parallel=4" \
    -e HOME="/tmp" \
    -e PACKAGE_ARCH="${package_arch}" \
    -e PACKAGE_NAME="${package_name}" \
    -e PACKAGE_VERSION="${package_version}" \
    -e SOURCE_DATE_EPOCH="0" \
    -v "${workdir}:/work" \
    "${docker_image}" \
    bash -lc "
set -euo pipefail

export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
export SWSSCOMMON_BUILD_JOBS='4'
export CONFIGURED_ARCH='${package_arch}'
for libclang in /usr/lib/llvm-*/lib; do
    if [[ -d \"\${libclang}\" ]]; then
        export LIBCLANG_PATH=\"\${libclang}\"
        break
    fi
done

cd /work/src
if compgen -G '/work/build-debs/*.deb' >/dev/null; then
    for build_dep in /work/build-debs/*.deb; do
        dpkg-deb -x "\${build_dep}" /
    done
fi
if compgen -G '/work/wheel-deps/*.whl' >/dev/null; then
    mkdir -p /work/python-wheels
    python3 -m pip install --no-cache-dir --no-deps --no-compile --target /work/python-wheels /work/wheel-deps/*.whl
    export PYTHONPATH="/work/python-wheels:\${PYTHONPATH:-}"
fi
dpkg-buildpackage -rfakeroot -b -us -uc -d ${build_profile_args}

shopt -s nullglob
matches=(/work/${deb_pattern})
if [[ \${#matches[@]} -ne 1 ]]; then
    echo 'Expected exactly one Debian artifact matching ${deb_pattern}, found' \${#matches[@]} >&2
    printf '%s\n' \"\${matches[@]}\" >&2
    exit 1
fi

cp \"\${matches[0]}\" /work/out/${package_name}_${package_version}_${package_arch}.deb
"

install "${out_dir}/${package_name}_${package_version}_${package_arch}.deb" "${output}"
