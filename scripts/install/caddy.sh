#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
EZ_DATA="${EZ_DATA:-$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)}"
CADDY_DATA_DIR="${CADDY_DATA_DIR:-/data/caddy}"
CADDY_COMPOSE_FILE="${CADDY_COMPOSE_FILE:-${CADDY_DATA_DIR}/docker-compose.yml}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:latest}"
CADDY_CONFIG_TYPE="${CADDY_CONFIG_TYPE:-caddyfile}"
CADDY_REPO="${CADDY_REPO:-lxhao61/integrated-examples}"
CADDY_VERSION="${CADDY_VERSION:-}"
CADDY_OS="${CADDY_OS:-linux}"
ARCH="${ARCH:-amd64}"
DOWNLOAD_URL="${DOWNLOAD_URL:-}"

if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] ${*}" >&2; }
    warn() { echo "[W] ${*}" >&2; }
    err() { echo "[E] ${*}" >&2; }
    suc() { echo "[S] ${*}" >&2; }
fi

get_github_mirror_prefix() {
    GITHUB_MIRROR_PREFIX="${GH_MIRROR:-${MIRROR:-}}"
    GITHUB_MIRROR_PREFIX=$(printf '%s' "${GITHUB_MIRROR_PREFIX}" | sed 's#/*$##')
    if [ -n "${GITHUB_MIRROR_PREFIX}" ]; then
        printf '%s/' "${GITHUB_MIRROR_PREFIX}"
    fi
}

download_file() {
    DOWNLOAD_SOURCE_URL="${1}"
    DOWNLOAD_DESTINATION="${2}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${DOWNLOAD_SOURCE_URL}" -o "${DOWNLOAD_DESTINATION}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${DOWNLOAD_DESTINATION}" "${DOWNLOAD_SOURCE_URL}"
    else
        err "Neither curl nor wget is available"
        return 1
    fi
}

build_download_url() {
    if [ -n "${DOWNLOAD_URL}" ]; then
        return 0
    fi
    GITHUB_DOWNLOAD_URL="https://github.com/${CADDY_REPO}/releases/download/${CADDY_VERSION}/caddy-${CADDY_OS}-${ARCH}.tar.gz"
    GITHUB_MIRROR_PREFIX=$(get_github_mirror_prefix)
    DOWNLOAD_URL="${GITHUB_MIRROR_PREFIX}${GITHUB_DOWNLOAD_URL}"
    if ! download_file "${DOWNLOAD_URL}" /dev/null; then
        if [ -n "${GITHUB_MIRROR_PREFIX:-}" ]; then
            DOWNLOAD_URL="${GITHUB_DOWNLOAD_URL}"
            if download_file "${DOWNLOAD_URL}" /dev/null; then
                export DOWNLOAD_URL
                return 0
            fi
        fi
        DOWNLOAD_URL="https://cdn.jsdelivr.net/gh/${CADDY_REPO}@${CADDY_VERSION}/caddy_${CADDY_OS}_${ARCH}"
        download_file "${DOWNLOAD_URL}" /dev/null || return 1
    fi
    export DOWNLOAD_URL
}

if ! command -v docker >/dev/null 2>&1; then
    info "Docker is not installed; skip Caddy installation"
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is unavailable; skip Caddy installation"
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND="docker compose"
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND="docker-compose"
else
    err "Docker Compose is unavailable; skip Caddy installation"
    exit 1
fi

mkdir -p "${CADDY_DATA_DIR}/config" "${CADDY_DATA_DIR}/data"

case "${CADDY_CONFIG_TYPE}" in
    json)
        CADDY_CONFIG_FILE="${CADDY_DATA_DIR}/config/caddy.json"
        if [ ! -f "${CADDY_CONFIG_FILE}" ]; then
            cat > "${CADDY_CONFIG_FILE}" <<'EOF'
{
  "apps": {
    "http": {
      "servers": {
        "srv0": {
          "listen": [":80"],
          "routes": [{"handle": [{"handler": "static_response", "body": "Hello, World!"}]}]
        }
      }
    }
  }
}
EOF
        fi
        CADDY_COMMAND="caddy run --config /etc/caddy/caddy.json --adapter json"
        ;;
    *)
        CADDY_CONFIG_FILE="${CADDY_DATA_DIR}/config/Caddyfile"
        if [ ! -f "${CADDY_CONFIG_FILE}" ]; then
            cat > "${CADDY_CONFIG_FILE}" <<'EOF'
:80 {
    respond "Hello, World!"
}
EOF
        fi
        CADDY_COMMAND="caddy run --config /etc/caddy/Caddyfile"
        ;;
esac

cat > "${CADDY_COMPOSE_FILE}" <<EOF
services:
    caddy:
        image: ${CADDY_IMAGE}
        container_name: caddy
        restart: unless-stopped
        ports:
            - "80:80"
            - "443:443"
            - "443:443/udp"
        command: ${CADDY_COMMAND}
        volumes:
            - ./config:/etc/caddy
            - ./data:/data
            - ./data:/config
EOF

(
    cd "${CADDY_DATA_DIR}"
    ${COMPOSE_COMMAND} -f "${CADDY_COMPOSE_FILE}" up -d
)

suc "Caddy Compose project started in ${CADDY_DATA_DIR}"
