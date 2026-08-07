#!/usr/bin/env sh
# Configure Docker log rotation and optional registry mirrors.

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] $*" >&2; }
    warn() { echo "[W] $*" >&2; }
    err() { echo "[E] $*" >&2; }
    suc() { echo "[S] $*" >&2; }
fi

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

if [ "${DOCKER_DISABLE_LOG_CONFIG}" = true ]; then
    info "Docker daemon configuration disabled by DOCKER_DISABLE_LOG_CONFIG"
    exit 0
fi

load_docker_daemon_library() {
    if [ -f "${SCRIPT_DIR}/../../lib/docker_daemon.sh" ]; then
        . "${SCRIPT_DIR}/../../lib/docker_daemon.sh"
        return $?
    fi

    DOCKER_DAEMON_LIBRARY=$(mktemp) || return 1
    DOCKER_LIBRARY_URL=${DOCKER_LIBRARY_URL:-${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/lib/docker_daemon.sh}
    info "Downloading Docker daemon configuration library"
    if ! download_file "${DOCKER_LIBRARY_URL}" "${DOCKER_DAEMON_LIBRARY}"; then
        rm -f "${DOCKER_DAEMON_LIBRARY}"
        err "Failed to download Docker daemon configuration library"
        return 1
    fi

    . "${DOCKER_DAEMON_LIBRARY}"
}

DOCKER_DAEMON_LIBRARY=""
trap 'rm -f "${DOCKER_DAEMON_LIBRARY}"' EXIT HUP INT TERM

if ! load_docker_daemon_library; then
    exit 1
fi

configure_docker_daemon
exit $?
