#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  build_review_docker_archive.sh \
    --mode docker_orchagent_review \
    --output <artifact.gz> \
    --image-name <docker-image-name> \
    --platform <docker-platform> \
    --base-image <base-image> \
    <src>...
EOF
}

mode=""
output=""
image_name=""
platform="linux/amd64"
base_image="debian:bookworm-slim"
declare -a srcs=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            mode="$2"
            shift 2
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        --image-name)
            image_name="$2"
            shift 2
            ;;
        --platform)
            platform="$2"
            shift 2
            ;;
        --base-image)
            base_image="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            srcs+=("$1")
            shift
            ;;
    esac
done

if [[ -z "${mode}" || -z "${output}" || -z "${image_name}" ]]; then
    usage
    exit 1
fi

if [[ "${mode}" != "docker_orchagent_review" ]]; then
    echo "Unsupported review build mode: ${mode}" >&2
    exit 1
fi

workdir="$(mktemp -d)"
context_dir="${workdir}/context"
image_tag="bazel-review/${image_name}:$(date +%s)-$$"

cleanup() {
    docker image rm -f "${image_tag}" >/dev/null 2>&1 || true
    rm -rf "${workdir}"
}
trap cleanup EXIT

mkdir -p \
    "${context_dir}/constants" \
    "${context_dir}/orchagent" \
    "${context_dir}/files" \
    "${context_dir}/redis-dump-load" \
    "${context_dir}/scapy" \
    "${context_dir}/sonic-config-engine" \
    "${context_dir}/sonic-py-common" \
    "${context_dir}/sonic-swss-common" \
    "${context_dir}/review"

copy_input() {
    local src="$1"
    local rel=""
    local dest=""

    case "${src}" in
        */dockers/docker-orchagent/*)
            rel="${src#*/dockers/docker-orchagent/}"
            dest="${context_dir}/orchagent/${rel}"
            ;;
        dockers/docker-orchagent/*)
            rel="${src#dockers/docker-orchagent/}"
            dest="${context_dir}/orchagent/${rel}"
            ;;
        */files/scripts/arp_update|files/scripts/arp_update)
            dest="${context_dir}/files/arp_update"
            ;;
        */files/build_templates/arp_update_vars.j2|files/build_templates/arp_update_vars.j2)
            dest="${context_dir}/files/arp_update_vars.j2"
            ;;
        */files/image_config/constants/constants.yml|files/image_config/constants/constants.yml)
            dest="${context_dir}/constants/constants.yml"
            ;;
        */src/scapy/*)
            rel="${src#*/src/scapy/}"
            dest="${context_dir}/scapy/${rel}"
            ;;
        src/scapy/*)
            rel="${src#src/scapy/}"
            dest="${context_dir}/scapy/${rel}"
            ;;
        */src/redis-dump-load/*)
            rel="${src#*/src/redis-dump-load/}"
            dest="${context_dir}/redis-dump-load/${rel}"
            ;;
        src/redis-dump-load/*)
            rel="${src#src/redis-dump-load/}"
            dest="${context_dir}/redis-dump-load/${rel}"
            ;;
        */src/sonic-py-common/*)
            rel="${src#*/src/sonic-py-common/}"
            dest="${context_dir}/sonic-py-common/${rel}"
            ;;
        src/sonic-py-common/*)
            rel="${src#src/sonic-py-common/}"
            dest="${context_dir}/sonic-py-common/${rel}"
            ;;
        */src/sonic-config-engine/*)
            rel="${src#*/src/sonic-config-engine/}"
            dest="${context_dir}/sonic-config-engine/${rel}"
            ;;
        src/sonic-config-engine/*)
            rel="${src#src/sonic-config-engine/}"
            dest="${context_dir}/sonic-config-engine/${rel}"
            ;;
        */src/sonic-swss-common/*)
            rel="${src#*/src/sonic-swss-common/}"
            dest="${context_dir}/sonic-swss-common/${rel}"
            ;;
        src/sonic-swss-common/*)
            rel="${src#src/sonic-swss-common/}"
            dest="${context_dir}/sonic-swss-common/${rel}"
            ;;
        *)
            echo "Unsupported review input: ${src}" >&2
            exit 1
            ;;
    esac

    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
}

for src in "${srcs[@]}"; do
    copy_input "${src}"
done

if [[ -f "${context_dir}/scapy/setup.py" && ! -f "${context_dir}/scapy/scapy/VERSION" ]]; then
    printf '0.0.dev0\n' > "${context_dir}/scapy/scapy/VERSION"
fi

cat > "${context_dir}/review/docker-init.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'BANNER'
SONiC Bazel review image: docker-orchagent
This is a Phase 1 concrete archive built by Bazel for review.
It now includes a local sonic-cfggen path and a generated docker-init.real.sh,
but it is not runtime-parity-complete with the legacy SONiC image yet.
BANNER

if [[ "${SONIC_BAZEL_REVIEW_REAL_INIT:-0}" == "1" ]]; then
    exec /usr/bin/docker-init.real.sh "$@"
fi

exec tail -f /dev/null
EOF

cat > "${context_dir}/review/sonic_yang_cfg_generator.py" <<'EOF'
class SonicYangCfgDbGenerator:
    def __init__(self, *args, **kwargs):
        raise RuntimeError(
            "sonic_yang_cfg_generator is not available in the Bazel review image. "
            "The review image supports non-YANG sonic-cfggen rendering paths only."
        )
EOF

cat > "${context_dir}/review/MIGRATION_STAGE.txt" <<'EOF'
docker-orchagent review image

- Built by Bazel as a concrete docker archive (.gz)
- Carries orchagent scripts/templates, local sonic-cfggen/config-engine, local scapy install, local swsscommon/sonic-db-cli, and local sonic-py-common
- Generates docker-init.real.sh from docker-init.j2 during image build
- Does not yet include full SWSS/SAI runtime parity or a booted CONFIG_DB/Redis environment
- Intended for image layout and dependency review before full hermetic migration
EOF

cat > "${context_dir}/Dockerfile" <<EOF
# syntax=docker/dockerfile:1.7
ARG BASE=${base_image}
FROM --platform=\$TARGETPLATFORM \$BASE

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \\
    arping \\
    autoconf \\
    autoconf-archive \\
    automake \\
    bash \\
    build-essential \\
    bridge-utils \\
    ca-certificates \\
    conntrack \\
    ifupdown \\
    iproute2 \\
    jq \\
    libboost-dev \\
    libboost-serialization-dev \\
    libboost-serialization1.74.0 \\
    libhiredis-dev \\
    libhiredis0.14 \\
    libnl-3-200 \\
    libnl-3-dev \\
    libnl-genl-3-200 \\
    libnl-genl-3-dev \\
    libnl-nf-3-200 \\
    libnl-nf-3-dev \\
    libnl-route-3-200 \\
    libnl-route-3-dev \\
    libpython3-dev \\
    libpython3.11 \\
    libtool \\
    libuuid1 \\
    libzmq3-dev \\
    libzmq5 \\
    m4 \\
    ndisc6 \\
    nlohmann-json3-dev \\
    ndppd \\
    pciutils \\
    pkg-config \\
    python3-bitarray \\
    python3-jinja2 \\
    python3-lxml \\
    python3 \\
    python3-netaddr \\
    python3-natsort \\
    python3-netifaces \\
    python3-packaging \\
    python3-pip \\
    python3-protobuf \\
    python3-redis \\
    python3-setuptools \\
    python3-yaml \\
    rsyslog \\
    swig \\
    supervisor \\
    tcpdump \\
    uuid-dev \\
 && python3 -m pip install --break-system-packages --no-cache-dir pyroute2==0.5.14 \\
 && rm -rf /var/lib/apt/lists/*

COPY orchagent /opt/sonic/docker-orchagent-src
COPY constants/constants.yml /etc/sonic/constants.yml
COPY files/arp_update /usr/bin/arp_update
COPY files/arp_update_vars.j2 /usr/share/sonic/templates/arp_update_vars.j2
COPY redis-dump-load /opt/sonic/redis-dump-load-src
COPY scapy /opt/sonic/scapy-src
COPY sonic-config-engine /opt/sonic/sonic-config-engine-src
COPY sonic-py-common /opt/sonic/sonic-py-common-src
COPY sonic-swss-common /opt/sonic/sonic-swss-common-src
COPY review/docker-init.sh /usr/bin/docker-init.sh
COPY review/MIGRATION_STAGE.txt /opt/sonic/review/MIGRATION_STAGE.txt
COPY review/sonic_yang_cfg_generator.py /opt/sonic/review/sonic_yang_cfg_generator.py

RUN mkdir -p \\
    /etc/sonic \\
    /opt/sonic/review \\
    /etc/supervisor/conf.d \\
    /var/run/redis/sonic-db \\
    /usr/share/sonic/hwsku \\
    /usr/share/sonic/platform \\
    /usr/share/sonic/templates \\
    /var/log/swss \\
    /zmq_swss \\
 && cd /opt/sonic/sonic-swss-common-src \\
 && ./autogen.sh \\
 && ./configure --enable-python2=no --enable-yangmodules=no \\
 && make -j"\$(nproc)" common/cfg_schema.h common/libswsscommon.la common/swssloglevel pyext/py3/_swsscommon.la sonic-db-cli/sonic-db-cli \\
 && SONIC_PURELIB="\$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \\
 && mkdir -p "\${SONIC_PURELIB}/swsscommon" \\
 && cp -P /opt/sonic/sonic-swss-common-src/common/.libs/libswsscommon.so* /usr/local/lib/ \\
 && cp /opt/sonic/sonic-swss-common-src/common/.libs/swssloglevel /usr/bin/swssloglevel \\
 && cp /opt/sonic/sonic-swss-common-src/common/database_config.json /var/run/redis/sonic-db/database_config.json \\
 && cp /opt/sonic/sonic-swss-common-src/sonic-db-cli/.libs/sonic-db-cli /usr/bin/sonic-db-cli \\
 && cp /opt/sonic/sonic-swss-common-src/pyext/py3/__init__.py "\${SONIC_PURELIB}/swsscommon/__init__.py" \\
 && cp /opt/sonic/sonic-swss-common-src/pyext/py3/swsscommon.py "\${SONIC_PURELIB}/swsscommon/swsscommon.py" \\
 && cp /opt/sonic/sonic-swss-common-src/pyext/py3/.libs/_swsscommon.so "\${SONIC_PURELIB}/swsscommon/_swsscommon.so" \\
 && ldconfig \\
 && python3 -m pip install --break-system-packages --no-cache-dir --no-deps /opt/sonic/redis-dump-load-src \\
 && python3 -m pip install --break-system-packages --no-cache-dir --no-deps /opt/sonic/sonic-py-common-src \\
 && python3 -m pip install --break-system-packages --no-cache-dir --no-deps /opt/sonic/scapy-src \\
 && mv /opt/sonic/sonic-config-engine-src/sonic_yang_cfg_generator.py /opt/sonic/sonic-config-engine-src/sonic_yang_cfg_generator.py.upstream \\
 && cp /opt/sonic/review/sonic_yang_cfg_generator.py /opt/sonic/sonic-config-engine-src/sonic_yang_cfg_generator.py \\
 && printf '%s\n' \\
    '#!/usr/bin/env bash' \\
    'set -euo pipefail' \\
    'export PYTHONPATH="/opt/sonic/sonic-config-engine-src:\${PYTHONPATH:-}"' \\
    'exec python3 /opt/sonic/sonic-config-engine-src/sonic-cfggen "\$@"' \\
    > /usr/local/bin/sonic-cfggen \\
 && chmod 755 /usr/local/bin/sonic-cfggen \\
 && cp /opt/sonic/docker-orchagent-src/arp_update.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/ndppd.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/tunnel_packet_handler.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/enable_counters.py /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/tunnel_packet_handler.py /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/orchagent.sh /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/swssconfig.sh /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/buffermgrd.sh /usr/bin/ \\
 && find /opt/sonic/docker-orchagent-src -maxdepth 1 -name '*.j2' -exec cp {} /usr/share/sonic/templates/ \; \\
 && /usr/local/bin/sonic-cfggen -a '{"ENABLE_ASAN":"n"}' -t /opt/sonic/docker-orchagent-src/docker-init.j2,/usr/bin/docker-init.real.sh \\
 && chmod 755 /usr/bin/docker-init.real.sh \\
 && /bin/bash -n /usr/bin/docker-init.real.sh \\
 && rm -rf /opt/sonic/sonic-config-engine-src/tests \\
 && find /opt/sonic/sonic-config-engine-src -type d -name __pycache__ -prune -exec rm -rf {} + \\
 && find /opt/sonic/sonic-config-engine-src -type f -name '*.pyc' -delete \\
 && rm -f \\
    /opt/sonic/sonic-config-engine-src/.gitignore \\
    /opt/sonic/sonic-config-engine-src/MANIFEST.in \\
    /opt/sonic/sonic-config-engine-src/setup.cfg \\
    /opt/sonic/sonic-config-engine-src/setup.py \\
    /opt/sonic/sonic-config-engine-src/sonic-acl-extension.yang \\
    /opt/sonic/sonic-config-engine-src/sonic_yang_cfg_generator.py.upstream \\
 && strip --strip-unneeded \\
    /usr/bin/sonic-db-cli \\
    /usr/bin/swssloglevel \\
    /usr/local/lib/libswsscommon.so.0.0.0 \\
    /usr/local/lib/python3.11/dist-packages/swsscommon/_swsscommon.so || true \\
 && apt-get purge -y --auto-remove \\
    autoconf \\
    autoconf-archive \\
    automake \\
    build-essential \\
    libboost-dev \\
    libboost-serialization-dev \\
    libhiredis-dev \\
    libnl-3-dev \\
    libnl-genl-3-dev \\
    libnl-nf-3-dev \\
    libnl-route-3-dev \\
    libpython3-dev \\
    libtool \\
    m4 \\
    nlohmann-json3-dev \\
    pkg-config \\
    python3-pip \\
    python3-wheel \\
    swig \\
    uuid-dev \\
    libzmq3-dev \\
 && apt-get clean \\
 && rm -rf \\
    /root/.cache/pip \\
    /usr/share/bash-completion \\
    /usr/share/bug \\
    /usr/share/doc \\
    /usr/share/ieee-data \\
    /usr/share/lintian \\
    /usr/share/man \\
    /var/cache/apt \\
    /var/lib/apt/lists/* \\
    /opt/sonic/redis-dump-load-src \\
    /opt/sonic/scapy-src \\
    /opt/sonic/sonic-py-common-src \\
    /opt/sonic/sonic-swss-common-src \\
 && find /usr/lib/python3/dist-packages -type d -name __pycache__ -prune -exec rm -rf {} + \\
 && find /usr/local/lib/python3.11/dist-packages -type d -name __pycache__ -prune -exec rm -rf {} + \\
 && find /usr/lib/python3/dist-packages -type f -name '*.pyc' -delete \\
 && find /usr/local/lib/python3.11/dist-packages -type f -name '*.pyc' -delete \\
 && chmod +x \\
    /usr/bin/arp_update \\
    /usr/bin/buffermgrd.sh \\
    /usr/bin/docker-init.sh \\
    /usr/bin/orchagent.sh \\
    /usr/bin/sonic-db-cli \\
    /usr/bin/swssconfig.sh \\
    /usr/bin/swssloglevel

LABEL org.opencontainers.image.title="${image_name}" \\
      org.opencontainers.image.description="Bazel review archive for SONiC ${image_name}" \\
      com.sonic.migration.stage="phase1_review_archive"

ENTRYPOINT ["/usr/bin/docker-init.sh"]
EOF

DOCKER_BUILDKIT=1 docker buildx build \
    --platform "${platform}" \
    --load \
    --tag "${image_tag}" \
    "${context_dir}"

flat_tag="${image_tag}-flat"
container_id="$(docker create "${image_tag}")"
trap 'docker rm -f "${container_id}" >/dev/null 2>&1 || true; docker image rm -f "${flat_tag}" >/dev/null 2>&1 || true; cleanup' EXIT

docker export "${container_id}" | docker import \
    --platform "${platform}" \
    -c 'ENTRYPOINT ["/usr/bin/docker-init.sh"]' \
    -c 'ENV DEBIAN_FRONTEND=noninteractive' \
    -c "LABEL org.opencontainers.image.title=${image_name}" \
    -c 'LABEL com.sonic.migration.stage=phase1_review_archive_flattened' \
    - "${flat_tag}" >/dev/null

mkdir -p "$(dirname "${output}")"
docker save "${flat_tag}" | gzip -n -c > "${output}"
