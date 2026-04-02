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
    "${context_dir}/orchagent" \
    "${context_dir}/files" \
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

cat > "${context_dir}/review/docker-init.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat <<'BANNER'
SONiC Bazel review image: docker-orchagent
This is a Phase 1 concrete archive built by Bazel for review.
It packages the current docker-orchagent scripts/templates and key runtime tools,
but it is not runtime-parity-complete with the legacy SONiC image yet.
BANNER

exec tail -f /dev/null
EOF

cat > "${context_dir}/review/MIGRATION_STAGE.txt" <<'EOF'
docker-orchagent review image

- Built by Bazel as a concrete docker archive (.gz)
- Carries orchagent scripts, templates, and core runtime packages
- Does not yet include full SWSS/SAI runtime parity or config-engine rendering
- Intended for image layout and dependency review before full hermetic migration
EOF

cat > "${context_dir}/Dockerfile" <<EOF
# syntax=docker/dockerfile:1.7
ARG BASE=${base_image}
FROM --platform=\$TARGETPLATFORM \$BASE

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \\
    arping \\
    bash \\
    bridge-utils \\
    ca-certificates \\
    conntrack \\
    ifupdown \\
    iproute2 \\
    jq \\
    ndisc6 \\
    ndppd \\
    pciutils \\
    python3 \\
    python3-netifaces \\
    python3-pip \\
    python3-protobuf \\
    rsyslog \\
    supervisor \\
    tcpdump \\
 && python3 -m pip install --break-system-packages --no-cache-dir pyroute2==0.5.14 \\
 && rm -rf /var/lib/apt/lists/*

COPY orchagent /opt/sonic/docker-orchagent-src
COPY files/arp_update /usr/bin/arp_update
COPY review/docker-init.sh /usr/bin/docker-init.sh
COPY review/MIGRATION_STAGE.txt /opt/sonic/review/MIGRATION_STAGE.txt

RUN mkdir -p \\
    /etc/sonic \\
    /etc/supervisor/conf.d \\
    /opt/sonic/review \\
    /usr/share/sonic/hwsku \\
    /usr/share/sonic/platform \\
    /usr/share/sonic/templates \\
    /var/log/swss \\
    /zmq_swss \\
 && cp /opt/sonic/docker-orchagent-src/arp_update.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/ndppd.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/tunnel_packet_handler.conf /usr/share/sonic/templates/ \\
 && cp /opt/sonic/docker-orchagent-src/enable_counters.py /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/tunnel_packet_handler.py /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/orchagent.sh /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/swssconfig.sh /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/buffermgrd.sh /usr/bin/ \\
 && cp /opt/sonic/docker-orchagent-src/base_image_files/swssloglevel /usr/bin/swssloglevel \\
 && find /opt/sonic/docker-orchagent-src -maxdepth 1 -name '*.j2' -exec cp {} /usr/share/sonic/templates/ \; \\
 && chmod +x \\
    /usr/bin/arp_update \\
    /usr/bin/buffermgrd.sh \\
    /usr/bin/docker-init.sh \\
    /usr/bin/orchagent.sh \\
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

mkdir -p "$(dirname "${output}")"
docker save "${image_tag}" | gzip -n -c > "${output}"
