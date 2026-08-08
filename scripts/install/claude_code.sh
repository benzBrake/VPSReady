#!/usr/bin/env sh
# Install the Anthropic Claude Code CLI through the mise-managed Node.js runtime.

set -e

SCRIPT_DIR=$(cd "$(dirname "${0}")" && pwd)
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] ${*}"; }
    warn() { echo "[W] ${*}"; }
    err() { echo "[E] ${*}"; }
    suc() { echo "[S] ${*}"; }
fi

CLI_PACKAGE='@anthropic-ai/claude-code'
CLI_COMMAND='claude'
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_REGISTRY=$(printf '%s' "${NPM_REGISTRY}" | sed 's#/$##g')
CLAUDE_BASE_URL=$(printf '%s' "${CLAUDE_BASE_URL:-}" | sed 's#/$##g')
CLAUDE_TOKEN="${CLAUDE_TOKEN:-}"
MISE_DEFAULT_BIN="${HOME:-}/.local/bin/mise"
MISE_COMMAND=""

is_valid_npm_registry() {
    case "${1}" in
        "")
            return 0
            ;;
        http://?*|https://?*)
            ;;
        *)
            return 1
            ;;
    esac

    case "${1}" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/%-]*)
            return 1
            ;;
    esac

    return 0
}

is_valid_token() {
    case "${1}" in
        ""|*[[:space:]]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

shell_quote() {
    printf '%s' "${1}" | sed "s/'/'\\\\''/g"
}

find_mise() {
    if command -v mise >/dev/null 2>&1; then
        MISE_COMMAND=$(command -v mise)
        return 0
    fi

    if [ -n "${HOME:-}" ] && [ -x "${MISE_DEFAULT_BIN}" ]; then
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

install_cli() {
    if [ -n "${NPM_REGISTRY}" ]; then
        "${MISE_COMMAND}" exec -- npm install --global \
            --registry "${NPM_REGISTRY}" "${CLI_PACKAGE}"
    else
        "${MISE_COMMAND}" exec -- npm install --global "${CLI_PACKAGE}"
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

configure_claude_code() {
    if [ -z "${CLAUDE_BASE_URL}" ] || [ -z "${CLAUDE_TOKEN}" ]; then
        info "Claude Code API configuration skipped: base URL or token is missing"
        return 0
    fi

    if ! is_valid_npm_registry "${CLAUDE_BASE_URL}"; then
        err "CLAUDE_BASE_URL must be an http:// or https:// URL"
        return 1
    fi

    if ! is_valid_token "${CLAUDE_TOKEN}"; then
        err "CLAUDE_TOKEN cannot contain whitespace"
        return 1
    fi

    if [ -z "${HOME:-}" ]; then
        err "HOME is required to configure Claude Code CLI"
        return 1
    fi

    CLAUDE_CONFIG_DIR="${HOME}/.config/vpsready"
    CLAUDE_ENV_FILE="${CLAUDE_CONFIG_DIR}/claude_code.env"
    CLAUDE_ENV_SOURCE_LINE='[ -f "${HOME}/.config/vpsready/claude_code.env" ] && . "${HOME}/.config/vpsready/claude_code.env"'

    if ! mkdir -p "${CLAUDE_CONFIG_DIR}"; then
        err "Failed to create ${CLAUDE_CONFIG_DIR}"
        return 1
    fi
    chmod 700 "${CLAUDE_CONFIG_DIR}"

    (
        umask 077
        printf "export ANTHROPIC_BASE_URL='%s'\n" "$(shell_quote "${CLAUDE_BASE_URL}")"
        printf "export ANTHROPIC_AUTH_TOKEN='%s'\n" "$(shell_quote "${CLAUDE_TOKEN}")"
    ) | (
        umask 077
        tee "${CLAUDE_ENV_FILE}" >/dev/null
    )
    chmod 600 "${CLAUDE_ENV_FILE}"

    ensure_line "${HOME}/.profile" "${CLAUDE_ENV_SOURCE_LINE}"
    ensure_line "${HOME}/.bashrc" "${CLAUDE_ENV_SOURCE_LINE}"
    suc "Claude Code API configuration saved"
}

if ! is_valid_npm_registry "${NPM_REGISTRY}"; then
    err "NPM_REGISTRY must be an http:// or https:// URL"
    exit 1
fi

if ! find_mise; then
    err "mise is required to install Claude Code CLI"
    exit 1
fi
ensure_mise_in_path

if "${MISE_COMMAND}" exec -- sh -c "command -v ${CLI_COMMAND} >/dev/null 2>&1"; then
    info "Claude Code CLI is already installed, skip"
else
    info "Installing ${CLI_PACKAGE}"
    if ! install_cli; then
        err "Failed to install Claude Code CLI"
        exit 1
    fi
fi

if ! "${MISE_COMMAND}" exec -- "${CLI_COMMAND}" --version; then
    err "Claude Code CLI installation verification failed"
    exit 1
fi

if ! configure_claude_code; then
    exit 1
fi

suc "Claude Code CLI is ready"
