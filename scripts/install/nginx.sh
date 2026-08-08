#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
EZ_DATA="${EZ_DATA:-$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)}"
NGINX_DATA_DIR="${NGINX_DATA_DIR:-/data/nginx}"
NGINX_COMPOSE_FILE="${NGINX_COMPOSE_FILE:-${NGINX_DATA_DIR}/docker-compose.yml}"
NGINX_IMAGE="${NGINX_IMAGE:-nginx:latest}"

info() { echo "[I] ${*}" >&2; }
err() { echo "[E] ${*}" >&2; }
suc() { echo "[S] ${*}" >&2; }

if ! command -v docker >/dev/null 2>&1; then
    info "Docker is not installed; skip Nginx installation"
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is unavailable; skip Nginx installation"
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND="docker compose"
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND="docker-compose"
else
    err "Docker Compose is unavailable; skip Nginx installation"
    exit 1
fi

mkdir -p "${NGINX_DATA_DIR}/conf.d" "${NGINX_DATA_DIR}/html" "${NGINX_DATA_DIR}/logs"

if [ ! -f "${NGINX_DATA_DIR}/nginx.conf" ]; then
    cp "${EZ_DATA}/web/demo-config/web.conf" "${NGINX_DATA_DIR}/nginx.conf"
    CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || awk '/^processor/ { count++ } END { print count + 0 }' /proc/cpuinfo)
    [ "${CORES}" -gt 0 ] 2>/dev/null || CORES=1
    sed -i "s/worker_processes.*/worker_processes  ${CORES};/" "${NGINX_DATA_DIR}/nginx.conf"
fi

cat > "${NGINX_COMPOSE_FILE}" <<EOF
services:
    nginx:
        image: ${NGINX_IMAGE}
        container_name: nginx
        restart: unless-stopped
        ports:
            - "80:80"
            - "443:443"
        volumes:
            - ./nginx.conf:/etc/nginx/nginx.conf:ro
            - ./conf.d:/etc/nginx/conf.d:ro
            - ./html:/usr/share/nginx/html
            - ./logs:/var/log/nginx
EOF

(
    cd "${NGINX_DATA_DIR}"
    ${COMPOSE_COMMAND} -f "${NGINX_COMPOSE_FILE}" up -d
)

suc "Nginx Compose project started in ${NGINX_DATA_DIR}"
