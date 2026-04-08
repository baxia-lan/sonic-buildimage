FROM debian@sha256:1d6cd964917a13b547d1ea392dff9a000c3f36070686ebc5c8755d53fb374435

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1

COPY tools/bazel/legacy_bridge_helper.apt.txt /tmp/legacy_bridge_helper.apt.txt
COPY tools/bazel/legacy_bridge_helper.requirements.txt /tmp/legacy_bridge_helper.requirements.txt

RUN apt-get update && apt-get install -y --no-install-recommends \
    $(tr '\n' ' ' < /tmp/legacy_bridge_helper.apt.txt) \
 && python3 -m pip install --break-system-packages --no-cache-dir -r /tmp/legacy_bridge_helper.requirements.txt \
 && rm -rf /var/lib/apt/lists/*
