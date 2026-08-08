#!/usr/bin/env sh
# mise 与最新 LTS Node.js 安装脚本

set -e

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(cd "$(dirname "${0}")" && pwd)
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
MISE_INSTALL_URL=${MISE_INSTALL_URL:-https://mise.run}
MISE_DEFAULT_BIN="${HOME}/.local/bin/mise"
MISE_COMMAND=""

find_mise() {
    if command -v mise >/dev/null 2>&1; then
        MISE_COMMAND=$(command -v mise)
        return 0
    fi

    if [ -x "${MISE_DEFAULT_BIN}" ]; then
        MISE_COMMAND="${MISE_DEFAULT_BIN}"
        return 0
    fi

    return 1
}

ensure_mise_in_path() {
    MISE_BIN_DIR=$(dirname "${MISE_COMMAND}")

    case ":${PATH}:" in
        *":${MISE_BIN_DIR}:"*)
            ;;
        *)
            PATH="${MISE_BIN_DIR}:${PATH}"
            export PATH
            ;;
    esac
}

install_mise() {
    if find_mise; then
        info "mise is already installed: ${MISE_COMMAND}"
        return 0
    fi

    info "Installing mise"
    MISE_INSTALLER=$(mktemp) || return 1
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fL "${MISE_INSTALL_URL}" -o "${MISE_INSTALLER}"; then
            rm -f "${MISE_INSTALLER}"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "${MISE_INSTALLER}" "${MISE_INSTALL_URL}"; then
            rm -f "${MISE_INSTALLER}"
            return 1
        fi
    else
        err "Neither curl nor wget is available"
        rm -f "${MISE_INSTALLER}"
        return 1
    fi

    if ! sh "${MISE_INSTALLER}"; then
        rm -f "${MISE_INSTALLER}"
        return 1
    fi
    rm -f "${MISE_INSTALLER}"

    if ! find_mise; then
        err "mise installation verification failed"
        return 1
    fi
}

ensure_line() {
    CONFIG_FILE="${1}"
    CONFIG_LINE="${2}"

    if [ ! -f "${CONFIG_FILE}" ]; then
        : >"${CONFIG_FILE}"
    fi

    if ! grep -Fqx "${CONFIG_LINE}" "${CONFIG_FILE}" >/dev/null 2>&1; then
        printf '%s\n' "${CONFIG_LINE}" >>"${CONFIG_FILE}"
    fi
}

configure_shell_environment() {
    MISE_PATH_LINE='export PATH="${HOME}/.local/bin:${PATH}"'
    MISE_SH_ACTIVATE_LINE='eval "$(mise activate sh)"'
    MISE_BASH_ACTIVATE_LINE='eval "$(mise activate bash)"'

    ensure_line "${HOME}/.profile" "${MISE_PATH_LINE}"
    ensure_line "${HOME}/.profile" "${MISE_SH_ACTIVATE_LINE}"
    ensure_line "${HOME}/.bashrc" "${MISE_PATH_LINE}"
    ensure_line "${HOME}/.bashrc" "${MISE_BASH_ACTIVATE_LINE}"
}

install_lts_node() {
    info "Installing the latest LTS Node.js release with mise"

    if ! "${MISE_COMMAND}" use --global node@lts; then
        err "Failed to install the latest LTS Node.js release"
        return 1
    fi
}

verify_installation() {
    if ! "${MISE_COMMAND}" exec -- node --version; then
        err "Node.js installation verification failed"
        return 1
    fi

    if ! "${MISE_COMMAND}" exec -- npm --version; then
        err "npm installation verification failed"
        return 1
    fi

    suc "mise and the latest LTS Node.js have been installed"
}

if [ -z "${HOME:-}" ]; then
    err "HOME is not set"
    exit 1
fi

install_mise
ensure_mise_in_path
configure_shell_environment
install_lts_node
verify_installation
