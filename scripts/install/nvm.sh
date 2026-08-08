#!/usr/bin/env sh
# NVM 与最新 LTS Node.js 安装脚本

set -e

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(dirname "$(readlink -f "${0}")")
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] ${*}"; }
    warn() { echo "[W] ${*}"; }
    err() { echo "[E] ${*}"; }
    suc() { echo "[S] ${*}"; }
fi

# ====================================
# 环境变量与默认值
# ====================================
NVM_DIR=${NVM_DIR:-${HOME}/.nvm}
NVM_INSTALL_URL=${NVM_INSTALL_URL:-https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh}
TMP_INSTALLER=""

cleanup() {
    if [ -n "${TMP_INSTALLER}" ] && [ -f "${TMP_INSTALLER}" ]; then
        rm -f "${TMP_INSTALLER}"
    fi
}

trap cleanup 0 1 2 15

# ====================================
# 检查安装依赖
# ====================================
check_dependencies() {
    if ! command -v bash >/dev/null 2>&1; then
        err "bash is required to install and use NVM"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to download the NVM installer"
        return 1
    fi
}

# ====================================
# 安装 NVM
# ====================================
install_nvm() {
    if [ -s "${NVM_DIR}/nvm.sh" ]; then
        info "NVM is already installed in ${NVM_DIR}"
        return 0
    fi

    info "Installing NVM"
    TMP_INSTALLER=$(mktemp)
    if ! curl -fL "${NVM_INSTALL_URL}" -o "${TMP_INSTALLER}"; then
        err "Failed to download the NVM installer"
        return 1
    fi

    if ! NVM_DIR="${NVM_DIR}" bash "${TMP_INSTALLER}"; then
        err "Failed to install NVM"
        return 1
    fi

    if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
        err "NVM installation verification failed"
        return 1
    fi
}

# ====================================
# 安装最新 LTS Node.js
# ====================================
install_lts_node() {
    info "Installing the latest LTS Node.js release"

    if ! NVM_DIR="${NVM_DIR}" bash -c '. "${NVM_DIR}/nvm.sh" && nvm install --lts && nvm alias default "lts/*"'; then
        err "Failed to install the latest LTS Node.js release"
        return 1
    fi
}

# ====================================
# 验证安装
# ====================================
verify_installation() {
    if ! NVM_DIR="${NVM_DIR}" bash -c '. "${NVM_DIR}/nvm.sh" && node --version && npm --version'; then
        err "Node.js installation verification failed"
        return 1
    fi

    suc "NVM and the latest LTS Node.js have been installed"
}

# ====================================
# 主流程
# ====================================
check_dependencies
install_nvm
install_lts_node
verify_installation
