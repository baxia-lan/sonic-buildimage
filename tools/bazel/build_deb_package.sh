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
helper_image_ref_script="tools/bazel/legacy_bridge_helper_image_ref.sh"
if [[ ! -x "${helper_image_ref_script}" ]]; then
    workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    helper_image_ref_script="${workspace_root}/tools/bazel/legacy_bridge_helper_image_ref.sh"
fi
if [[ -z "${docker_image}" ]]; then
    docker_image="$("${helper_image_ref_script}")"
fi
workdir="$(mktemp -d)"
stage_dir="${workdir}/src"
out_dir="${workdir}/out"
mkdir -p "${stage_dir}" "${out_dir}"

cleanup() {
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

if find "${stage_dir}" -name Cargo.toml -print -quit | grep -q .; then
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

"${docker_bin}" run --rm \
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
dpkg-buildpackage -rfakeroot -b -us -uc -d -Pnoyangmod,nopython2

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
