#!/usr/bin/env sh
# Glow 安装脚本 - Markdown 终端渲染工具

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/../.utils/common.sh" ]; then
    . "${SCRIPT_DIR}/../.utils/common.sh"
else
    # 如果 common.sh 不可用，定义基本日志函数
    info() { echo "[I] $*"; }
    warn() { echo "[W] $*"; }
    err() { echo "[E] $*"; }
    suc() { echo "[S] $*"; }
fi

# ====================================
# 环境变量与默认值
# ====================================
GLOW_VERSION=${GLOW_VERSION:-latest}
GLOW_INSTALL_DIR=${GLOW_INSTALL_DIR:-/usr/local/bin}
GLOW_MIRROR=${GLOW_MIRROR:-https://github.com}

# ====================================
# 检测系统架构
# ====================================
detect_architecture() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
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
    case "$(uname -s)" in
        Linux)
            echo "Linux"
            ;;
        Darwin)
            echo "Darwin"
            ;;
        *)
            err "Unsupported OS: $(uname -s)"
            return 1
            ;;
    esac
}

# ====================================
# 尝试通过 go install 安装（备选方案）
# ====================================
install_via_go() {
    info "Attempting installation via 'go install'"

    # 检查 go 是否安装
    if ! command -v go >/dev/null 2>&1; then
        warn "Go is not installed, skipping go install method"
        return 1
    fi

    # 设置 Go 环境变量（如果需要）
    if [ -z "${GOPATH}" ]; then
        GOPATH="${HOME}/go"
    fi

    # 安装
    if go install github.com/charmbracelet/glow@latest 2>/dev/null; then
        # 复制到目标目录
        if [ -f "${GOPATH}/bin/glow" ]; then
            cp "${GOPATH}/bin/glow" "${GLOW_INSTALL_DIR}/"
            chmod +x "${GLOW_INSTALL_DIR}/glow"
            suc "Glow installed successfully via go install"
            return 0
        fi
    fi

    warn "go install method failed"
    return 1
}

# ====================================
# 下载 Glow
# ====================================
download_glow() {
    ARCH=$1
    OS=$2
    VERSION=$3

    info "Downloading Glow for ${OS}_${ARCH}"

    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}" || {
        err "Failed to enter temporary directory"
        return 1
    }

    # 构建 BASE_URL
    if [ "${VERSION}" = "latest" ]; then
        BASE_URL="${GLOW_MIRROR}/charmbracelet/glow/releases/latest/download"
        # 获取最新版本号（用于构建文件名）
        ACTUAL_VERSION=$(curl -fsSL "${GLOW_MIRROR}/charmbracelet/glow/releases/latest" | grep -o 'tag/[vV][0-9][^"]*' | sed 's/tag\///' | head -1)
        if [ -z "${ACTUAL_VERSION}" ]; then
            # 备选方案：尝试从 API 获取
            ACTUAL_VERSION=$(curl -fsSL "https://api.github.com/repos/charmbracelet/glow/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        fi
        if [ -z "${ACTUAL_VERSION}" ]; then
            warn "Failed to determine latest version number, trying without version in filename"
            ACTUAL_VERSION=""
        else
            info "Latest version: ${ACTUAL_VERSION}"
        fi
    else
        BASE_URL="${GLOW_MIRROR}/charmbracelet/glow/releases/download/${VERSION}"
        ACTUAL_VERSION="${VERSION}"
    fi

    # 去除版本号中的 'v' 前缀（如果有）
    ACTUAL_VERSION=$(echo "${ACTUAL_VERSION}" | sed 's/^v//')

    # 构建可能的下载 URL 列表
    # 主要格式: glow_2.1.1_Linux_x86_64.tar.gz (Charmbracelet/Goreleaser 标准格式)
    # 备选格式: glow-linux-amd64.tar.gz
    if [ -n "${ACTUAL_VERSION}" ]; then
        URLS="${BASE_URL}/glow_${ACTUAL_VERSION}_${OS}_${ARCH}.tar.gz"
        URLS="${URLS} ${BASE_URL}/glow-${OS}-$(echo ${ARCH} | sed 's/x86_64/amd64/;s/arm64/aarch64/').tar.gz"
    else
        # 如果无法获取版本号，尝试不带版本号的格式
        URLS="${BASE_URL}/glow_${OS}_${ARCH}.tar.gz"
        URLS="${URLS} ${BASE_URL}/glow-${OS}-$(echo ${ARCH} | sed 's/x86_64/amd64/;s/arm64/aarch64/').tar.gz"
    fi

    # 尝试每个 URL 直到成功
    for url in ${URLS}; do
        info "Trying: ${url}"
        if curl -fsSL "${url}" -o glow.tar.gz 2>/dev/null; then
            info "Successfully downloaded from: ${url}"
            DOWNLOAD_URL="${url}"
            break
        fi
    done

    # 检查是否下载成功
    if [ ! -f glow.tar.gz ] || [ ! -s glow.tar.gz ]; then
        err "Failed to download Glow from all attempted URLs"
        err "Tried URLs: ${URLS}"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 解压文件
    if ! tar -xzf glow.tar.gz 2>/dev/null; then
        err "Failed to extract Glow archive"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 查找 glow 二进制文件（可能在子目录）
    GLOW_BIN=""
    if [ -f glow ]; then
        GLOW_BIN="glow"
    elif [ -f glow/glow ]; then
        GLOW_BIN="glow/glow"
    else
        # 查找任意包含 glow 的可执行文件
        GLOW_BIN=$(find . -type f -name "glow" -executable 2>/dev/null | head -1)
    fi

    if [ -z "${GLOW_BIN}" ] || [ ! -f "${GLOW_BIN}" ]; then
        err "Cannot find glow binary in archive"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 安装二进制文件
    info "Installing Glow to ${GLOW_INSTALL_DIR}"
    if ! cp "${GLOW_BIN}" "${GLOW_INSTALL_DIR}/glow"; then
        err "Failed to copy Glow to ${GLOW_INSTALL_DIR}"
        cd - >/dev/null
        rm -rf "${TMP_DIR}"
        return 1
    fi

    # 设置可执行权限
    chmod +x "${GLOW_INSTALL_DIR}/glow"

    # 清理临时目录
    cd - >/dev/null
    rm -rf "${TMP_DIR}"

    suc "Glow downloaded and installed successfully"
    return 0
}

# ====================================
# 验证安装
# ====================================
verify_installation() {
    if command -v glow >/dev/null 2>&1; then
        GLOW_VERSION_OUTPUT=$(glow --version 2>&1)
        suc "Glow installed successfully: ${GLOW_VERSION_OUTPUT}"
        return 0
    else
        err "Glow installation verification failed"
        return 1
    fi
}

# ====================================
# 主安装流程
# ====================================
install_glow() {
    info "Starting Glow installation"

    # 检查是否已安装
    if command -v glow >/dev/null 2>&1; then
        info "Glow is already installed"
        if [ "${FORCE_REINSTALL}" != "true" ]; then
            glow --version
            return 0
        else
            info "FORCE_REINSTALL is set, reinstalling..."
        fi
    fi

    # 检测架构和操作系统
    ARCH=$(detect_architecture) || {
        err "Failed to detect architecture"
        return 1
    }
    info "Detected architecture: ${ARCH}"

    OS=$(detect_os) || {
        err "Failed to detect OS"
        return 1
    }
    info "Detected OS: ${OS}"

    # 下载并安装
    if ! download_glow "${ARCH}" "${OS}" "${GLOW_VERSION}"; then
        warn "Binary download failed, trying alternative installation method..."
        if ! install_via_go; then
            err "All installation methods failed"
            return 1
        fi
    fi

    # 验证安装
    if ! verify_installation; then
        err "Glow installation verification failed"
        return 1
    fi

    suc "Glow installation completed successfully"
    return 0
}

# ====================================
# 主流程
# ====================================

# 如果直接运行此脚本，执行安装
if [ "$(basename "$0")" = "glow.sh" ]; then
    install_glow
    exit $?
fi
