#!/usr/bin/env sh
# Install Docker and configure daemon defaults for Debian, Ubuntu, and Alpine.

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
    DOWNLOAD_QUIET="${3:-false}"

    if [ "${DOWNLOAD_DESTINATION}" = /dev/null ] || [ "${DOWNLOAD_QUIET}" = true ]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "${DOWNLOAD_SOURCE_URL}" -o "${DOWNLOAD_DESTINATION}"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "${DOWNLOAD_DESTINATION}" "${DOWNLOAD_SOURCE_URL}"
        else
            err "Neither curl nor wget is available"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        curl -fL "${DOWNLOAD_SOURCE_URL}" -o "${DOWNLOAD_DESTINATION}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${DOWNLOAD_DESTINATION}" "${DOWNLOAD_SOURCE_URL}"
    else
        err "Neither curl nor wget is available"
        return 1
    fi
}

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

DOCKER_INSTALL_MIRROR=${DOCKER_INSTALL_MIRROR:-}
DOCKER_INSTALLER_URL=${DOCKER_INSTALLER_URL:-https://get.docker.com}

validate_install_mirror() {
    case "${DOCKER_INSTALL_MIRROR}" in
        ""|Aliyun|AzureChinaCloud)
            return 0
            ;;
        *)
            err "DOCKER_INSTALL_MIRROR must be Aliyun or AzureChinaCloud"
            return 1
            ;;
    esac
}

get_cn_download_url() {
    case "${DOCKER_INSTALL_MIRROR}" in
        ""|Aliyun)
            printf '%s' 'https://mirrors.aliyun.com/docker-ce'
            ;;
        AzureChinaCloud)
            printf '%s' 'https://mirror.azure.cn/docker-ce'
            ;;
    esac
}

install_docker_from_official_script() {
    DOCKER_INSTALLER=$(mktemp) || return 1

    info "Downloading Docker installer from ${DOCKER_INSTALLER_URL}"
    if ! download_file "${DOCKER_INSTALLER_URL}" "${DOCKER_INSTALLER}"; then
        rm -f "${DOCKER_INSTALLER}"
        return 1
    fi

    if [ -n "${DOCKER_INSTALL_MIRROR}" ]; then
        sh "${DOCKER_INSTALLER}" --mirror "${DOCKER_INSTALL_MIRROR}"
    else
        sh "${DOCKER_INSTALLER}"
    fi
    DOCKER_INSTALL_RESULT=$?
    rm -f "${DOCKER_INSTALLER}"
    return "${DOCKER_INSTALL_RESULT}"
}

install_docker_from_cn_apt_repo() {
    DOCKER_OS_RELEASE_FILE=${DOCKER_OS_RELEASE_FILE:-/etc/os-release}
    if [ ! -r "${DOCKER_OS_RELEASE_FILE}" ]; then
        err "Cannot determine Linux distribution"
        return 1
    fi

    . "${DOCKER_OS_RELEASE_FILE}"
    case "${ID}" in
        debian|ubuntu)
            ;;
        *)
            err "Unsupported APT distribution: ${ID}"
            return 1
            ;;
    esac

    DOCKER_DISTRO="${ID}"
    DOCKER_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME}}"
    if [ -z "${DOCKER_CODENAME}" ]; then
        err "Cannot determine distribution codename"
        return 1
    fi

    DOCKER_DOWNLOAD_URL=$(get_cn_download_url)
    DOCKER_KEYRING_DIR=${DOCKER_APT_KEYRING_DIR:-/etc/apt/keyrings}
    DOCKER_KEYRING_FILE=${DOCKER_KEYRING_DIR}/docker.asc
    DOCKER_APT_SOURCE=${DOCKER_APT_SOURCE_FILE:-/etc/apt/sources.list.d/docker.list}

    info "Installing Docker from ${DOCKER_DOWNLOAD_URL}"
    if ! apt-get update; then
        return 1
    fi
    if ! apt-get -y install ca-certificates curl; then
        return 1
    fi
    if ! install -m 0755 -d "${DOCKER_KEYRING_DIR}"; then
        return 1
    fi
    if ! download_file "${DOCKER_DOWNLOAD_URL}/linux/${DOCKER_DISTRO}/gpg" "${DOCKER_KEYRING_FILE}"; then
        return 1
    fi
    if ! chmod a+r "${DOCKER_KEYRING_FILE}"; then
        return 1
    fi

    printf '%s\n' \
        "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEYRING_FILE}] ${DOCKER_DOWNLOAD_URL}/linux/${DOCKER_DISTRO} ${DOCKER_CODENAME} stable" \
        > "${DOCKER_APT_SOURCE}"
    if [ $? -ne 0 ]; then
        err "Failed to write ${DOCKER_APT_SOURCE}"
        return 1
    fi

    if ! apt-get update; then
        return 1
    fi

    if [ -z "${NOT_INSTALL_DOCKER_COMPOSE}" ]; then
        apt-get -y install \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin
        return $?
    fi

    apt-get -y install \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin
}

install_docker_from_apk() {
    info "Installing Docker from Alpine packages"
    if ! apk add --no-cache docker; then
        return 1
    fi

    if [ -z "${NOT_INSTALL_DOCKER_COMPOSE}" ]; then
        if ! apk add --no-cache docker-cli-compose; then
            warn "docker-cli-compose is unavailable; trying docker-compose"
            apk add --no-cache docker-compose
        fi
    fi
}

enable_and_start_docker() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker && return 0
        systemctl enable --now docker.service && return 0
    fi

    if command -v rc-update >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
        rc-update add docker boot && rc-service docker start && return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service docker start && return 0
    fi

    warn "Docker was installed but could not be started automatically"
    return 1
}

ensure_json_parser() {
    if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    info "Installing jq for Docker daemon configuration"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get -y install jq
        return $?
    fi

    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache jq
        return $?
    fi

    return 1
}

install_docker() {
    if ! validate_install_mirror; then
        return 1
    fi

    if command -v apk >/dev/null 2>&1; then
        install_docker_from_apk
        return $?
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        err "Only Debian, Ubuntu, and Alpine are supported"
        return 1
    fi

    if [ "${DOCKER_REGION}" = cn ]; then
        install_docker_from_cn_apt_repo
        return $?
    fi

    install_docker_from_official_script
}

info "Installing Docker"
if ! install_docker; then
    err "Docker installation failed"
    exit 1
fi

if ! enable_and_start_docker; then
    warn "Continue without automatic Docker service startup"
fi

if [ -z "${NOT_INSTALL_DOCKER_COMPOSE}" ]; then
    if docker compose version >/dev/null 2>&1; then
        suc "Docker Compose is available"
    else
        warn "Docker Compose is unavailable after installation"
    fi
fi

if [ "${DOCKER_DISABLE_LOG_CONFIG}" != true ]; then
    sleep 2
    if ensure_json_parser && configure_docker_daemon; then
        suc "Docker installation and daemon configuration completed"
    else
        warn "Docker installed but daemon configuration failed"
    fi
else
    info "Docker daemon configuration disabled by DOCKER_DISABLE_LOG_CONFIG"
fi

DOCKER_IPTABLES_SCRIPT=${SCRIPT_DIR}/../configure/docker_iptables.sh
if command -v docker >/dev/null 2>&1 && [ -f "${DOCKER_IPTABLES_SCRIPT}" ]; then
    if "${DOCKER_IPTABLES_SCRIPT}"; then
        suc "Docker port whitelist configuration completed"
    else
        warn "Docker installed but port whitelist configuration failed"
    fi
fi
