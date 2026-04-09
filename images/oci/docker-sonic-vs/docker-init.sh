#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/sonic /etc/supervisor/conf.d /var/log/supervisor /var/run/redis/sonic-db
echo "docker-sonic-vs" >/etc/hostname

ENABLE_ASAN="${ENABLE_ASAN:-n}"
sonic-cfggen \
    -a "{\"ENABLE_ASAN\":\"${ENABLE_ASAN}\"}" \
    -t /usr/share/sonic/templates/supervisord.conf.j2 \
    >/etc/supervisor/conf.d/supervisord.conf

exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
