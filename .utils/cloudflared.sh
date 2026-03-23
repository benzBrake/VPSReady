#!/bin/sh
# cloudflared 安装与执行工具脚本
# 用法: .utils/cloudflared.sh [参数]
# 如果 cloudflared 未安装，会先安装再执行命令

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    . "${SCRIPT_DIR}/common.sh"
else
    # 如果 common.sh 不可用，定义基本日志函数
    info() { echo "[I] $*" >&2; }
    warn() { echo "[W] $*" >&2; }
    err() { echo "[E] $*" >&2; }
    suc() { echo "[S] $*" >&2; }
fi

# ====================================
# 常量定义
# ====================================
CLOUDFLARED_VERSION=${CLOUDFLARED_VERSION:-latest}
CLOUDFLARED_BIN=${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}
CLOUDFLARED_DOWNLOAD_BASE=${CLOUDFLARED_DOWNLOAD_BASE:-https://github.com/cloudflare/cloudflared/releases}

# ====================================
# 检测系统架构
# ====================================
detect_architecture() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64|amd64)
            echo "amd64"
            ;;
        i386|i686)
            echo "386"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            err "Unsupported architecture: ${ARCH}"
            return 1
            ;;
    esac
}

# ====================================
# 检测操作系统类型
# ====================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        err "Unable to detect OS type"
        return 1
    fi
}

# ====================================
# 下载 cloudflared 二进制文件（通用方法）
# ====================================
download_cloudflared_binary() {
    info "Downloading cloudflared binary..."

    ARCH=$(detect_architecture) || return 1
    OS=$(detect_os) || return 1

    # Alpine 也使用 linux 作为操作系统标识
    case "${OS}" in
        alpine|debian|ubuntu)
            OS="linux"
            ;;
    esac

    if [ "${CLOUDFLARED_VERSION}" = "latest" ]; then
        DOWNLOAD_URL="${CLOUDFLARED_DOWNLOAD_BASE}/latest/download/cloudflared-${OS}-${ARCH}"
    else
        DOWNLOAD_URL="${CLOUDFLARED_DOWNLOAD_BASE}/download/${CLOUDFLARED_VERSION}/cloudflared-${OS}-${ARCH}"
    fi

    info "Download URL: ${DOWNLOAD_URL}"

    # 创建临时文件
    TEMP_FILE=$(mktemp)
    trap "rm -f ${TEMP_FILE}" EXIT

    # 下载文件
    if command -v wget >/dev/null 2>&1; then
        if ! wget -q -O "${TEMP_FILE}" "${DOWNLOAD_URL}"; then
            err "Failed to download cloudflared with wget"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "${DOWNLOAD_URL}" -o "${TEMP_FILE}"; then
            err "Failed to download cloudflared with curl"
            return 1
        fi
    else
        err "Neither wget nor curl is available"
        return 1
    fi

    # 移动到目标位置
    if ! mv "${TEMP_FILE}" "${CLOUDFLARED_BIN}"; then
        err "Failed to install cloudflared to ${CLOUDFLARED_BIN}"
        return 1
    fi

    # 添加执行权限
    chmod +x "${CLOUDFLARED_BIN}"

    suc "cloudflared installed successfully"
    return 0
}

# ====================================
# 在 Debian/Ubuntu 上安装 cloudflared
# ====================================
install_cloudflared_debian() {
    info "Installing cloudflared on Debian/Ubuntu..."

    # 尝试使用包管理器安装
    if command -v apt-get >/dev/null 2>&1; then
        # 添加 Cloudflare GPG 密钥
        if ! wget -q -O /tmp/cloudflared.gpg https://pkg.cloudflare.com/cloudflare-main.gpg 2>/dev/null; then
            warn "Failed to download GPG key, falling back to binary installation"
            return 1
        fi

        # 验证并添加密钥
        if ! gpg --dearmor -o /usr/share/keyrings/cloudflared-keyring.gpg /tmp/cloudflared.gpg 2>/dev/null; then
            warn "Failed to process GPG key, falling back to binary installation"
            rm -f /tmp/cloudflared.gpg
            return 1
        fi
        rm -f /tmp/cloudflared.gpg

        # 添加仓库
        echo 'deb [signed-by=/usr/share/keyrings/cloudflared-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list

        # 更新并安装
        apt-get update
        if apt-get install -y cloudflared; then
            suc "cloudflared installed via package manager"
            return 0
        fi
    fi

    return 1
}

# ====================================
# 在 Alpine 上安装 cloudflared
# ====================================
install_cloudflared_alpine() {
    info "Installing cloudflared on Alpine..."

    # Alpine 没有官方包，直接下载二进制
    if download_cloudflared_binary; then
        suc "cloudflared installed on Alpine"
        return 0
    fi

    return 1
}

# ====================================
# 安装 cloudflared
# ====================================
install_cloudflared() {
    info "Installing cloudflared..."

    OS=$(detect_os) || return 1

    case "${OS}" in
        debian|ubuntu)
            if install_cloudflared_debian; then
                return 0
            else
                warn "Package installation failed, trying binary installation..."
                download_cloudflared_binary
                return $?
            fi
            ;;
        alpine)
            install_cloudflared_alpine
            return $?
            ;;
        *)
            warn "Unsupported OS: ${OS}, trying binary installation..."
            download_cloudflared_binary
            return $?
            ;;
    esac
}

# ====================================
# 检查 cloudflared 是否已安装
# ====================================
check_cloudflared_installed() {
    if command -v cloudflared >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ====================================
# 主流程
# ====================================
main() {
    # 检查是否已安装
    if check_cloudflared_installed; then
        info "cloudflared is already installed"
        CLOUDFLARED_CMD=$(command -v cloudflared)
    else
        info "cloudflared not found, installing..."
        if ! install_cloudflared; then
            err "Failed to install cloudflared"
            return 1
        fi
        CLOUDFLARED_CMD="${CLOUDFLARED_BIN}"
    fi

    # 执行命令
    if [ $# -gt 0 ]; then
        info "Executing: cloudflared $*"
        exec "${CLOUDFLARED_CMD}" "$@"
    else
        # 如果没有参数，显示帮助信息
        info "cloudflared is ready"
        info "Usage: $0 [cloudflared options]"
        info "Example: $0 --version"
        exec "${CLOUDFLARED_CMD}" --help
    fi
}

# 执行主流程
main "$@"
