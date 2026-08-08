#!/usr/bin/env sh
# Rclone 安装脚本 - 从 GitHub Releases 下载预编译二进制

set -e

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] $*"; }
    warn() { echo "[W] $*"; }
    err() { echo "[E] $*"; }
    suc() { echo "[S] $*"; }
fi

# ====================================
# 环境变量与默认值
# ====================================
RCLONE_VERSION=${RCLONE_VERSION:-latest}
RCLONE_INSTALL_DIR=${RCLONE_INSTALL_DIR:-/usr/local/bin}
RCLONE_MIRROR=${RCLONE_MIRROR:-${GH_MIRROR:-https://github.com}}
RCLONE_REPO="rclone/rclone"

# ====================================
# 下载文件
# ====================================
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

# ====================================
# 检测系统架构
# ====================================
detect_architecture() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm-v7"
            ;;
        *)
            err "Unsupported architecture: ${ARCH}"
            return 1
            ;;
    esac
}

# ====================================
# 获取最新版本号
# ====================================
get_latest_version() {
    RELEASE_METADATA=$(mktemp)
    if download_file "https://api.github.com/repos/${RCLONE_REPO}/releases/latest" "${RELEASE_METADATA}" true; then
        TAG=$(grep '"tag_name"' "${RELEASE_METADATA}" | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    rm -f "${RELEASE_METADATA}"
    if [ -z "${TAG}" ]; then
        err "Failed to determine latest Rclone version"
        return 1
    fi
    echo "${TAG}"
}

# ====================================
# 下载并安装 Rclone
# ====================================
download_rclone() {
    ARCH=$1
    VERSION=$2

    info "Downloading Rclone ${VERSION} for linux-${ARCH}"

    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}" || {
        err "Failed to enter temporary directory"
        return 1
    }

    FILENAME="rclone-${VERSION}-linux-${ARCH}.zip"
    DOWNLOAD_URL="${RCLONE_MIRROR}/${RCLONE_REPO}/releases/download/${VERSION}/${FILENAME}"

    info "Downloading: ${DOWNLOAD_URL}"

    if ! download_file "${DOWNLOAD_URL}" rclone.zip; then
        err "Failed to download Rclone from ${DOWNLOAD_URL}"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 解压
    if ! unzip -o rclone.zip >/dev/null; then
        err "Failed to extract Rclone archive"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 查找二进制文件
    RCLONE_BIN=$(find . -type f -name "rclone" -executable 2>/dev/null | head -1)
    if [ -z "${RCLONE_BIN}" ]; then
        err "Cannot find rclone binary in archive"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 安装
    info "Installing Rclone to ${RCLONE_INSTALL_DIR}"
    cp "${RCLONE_BIN}" "${RCLONE_INSTALL_DIR}/rclone"
    chmod +x "${RCLONE_INSTALL_DIR}/rclone"

    # 清理
    cd - >/dev/null
    rm -rf "${TMP_DIR}"

    suc "Rclone downloaded and installed successfully"
    return 0
}

# ====================================
# 验证安装
# ====================================
verify_installation() {
    if command -v rclone >/dev/null 2>&1; then
        RCLONE_VERSION_OUTPUT=$(rclone version 2>&1 | head -1)
        suc "Rclone installed: ${RCLONE_VERSION_OUTPUT}"
        return 0
    else
        err "Rclone installation verification failed"
        return 1
    fi
}

# ====================================
# 主安装流程
# ====================================
install_rclone() {
    info "Starting Rclone installation"

    if command -v rclone >/dev/null 2>&1; then
        info "Rclone is already installed"
        if [ "${FORCE_REINSTALL}" != "true" ]; then
            rclone version | head -1
            return 0
        else
            info "FORCE_REINSTALL is set, reinstalling..."
        fi
    fi

    ARCH=$(detect_architecture) || {
        err "Failed to detect architecture"
        return 1
    }
    info "Detected architecture: ${ARCH}"

    if [ "${RCLONE_VERSION}" = "latest" ]; then
        VERSION=$(get_latest_version) || return 1
    else
        VERSION="v${RCLONE_VERSION#v}"
    fi
    info "Target version: ${VERSION}"

    if ! download_rclone "${ARCH}" "${VERSION}"; then
        err "Rclone installation failed"
        return 1
    fi

    if ! verify_installation; then
        err "Rclone installation verification failed"
        return 1
    fi

    suc "Rclone installation completed successfully"
    return 0
}

install_rclone
exit $?
