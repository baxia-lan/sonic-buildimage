FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    docker.io \
    gawk \
    git \
    jq \
    kmod \
    make \
    passwd \
    python3 \
    python3-pip \
    sudo \
    wget \
 && python3 -m pip install --break-system-packages --no-cache-dir jinjanator \
 && rm -rf /var/lib/apt/lists/*
