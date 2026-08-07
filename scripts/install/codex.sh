#!/usr/bin/env sh
# Install the OpenAI Codex CLI through the mise-managed Node.js runtime.

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

CLI_PACKAGE='@openai/codex'
CLI_COMMAND='codex'
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_REGISTRY=$(printf '%s' "${NPM_REGISTRY}" | sed 's#/$##g')
CODEX_BASE_URL=$(printf '%s' "${CODEX_BASE_URL:-}" | sed 's#/$##g')
CODEX_TOKEN="${CODEX_TOKEN:-}"
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

install_cli() {
    if [ -n "${NPM_REGISTRY}" ]; then
        "${MISE_COMMAND}" exec -- npm install --global \
            --registry "${NPM_REGISTRY}" "${CLI_PACKAGE}"
    else
        "${MISE_COMMAND}" exec -- npm install --global "${CLI_PACKAGE}"
    fi
}

configure_codex() {
    if [ -z "${CODEX_BASE_URL}" ] || [ -z "${CODEX_TOKEN}" ]; then
        info "Codex API configuration skipped: base URL or token is missing"
        return 0
    fi

    if ! is_valid_npm_registry "${CODEX_BASE_URL}"; then
        err "CODEX_BASE_URL must be an http:// or https:// URL"
        return 1
    fi

    if ! is_valid_token "${CODEX_TOKEN}"; then
        err "CODEX_TOKEN cannot contain whitespace"
        return 1
    fi

    if [ -z "${HOME:-}" ]; then
        err "HOME is required to configure Codex CLI"
        return 1
    fi

    CODEX_CONFIG_DIR="${HOME}/.codex"
    CODEX_CONFIG_FILE="${CODEX_CONFIG_DIR}/config.toml"

    if ! mkdir -p "${CODEX_CONFIG_DIR}"; then
        err "Failed to create ${CODEX_CONFIG_DIR}"
        return 1
    fi
    CODEX_CONFIG_TEMP=$(mktemp "${CODEX_CONFIG_FILE}.XXXXXX") || return 1

    printf 'openai_base_url = "%s"\n' "${CODEX_BASE_URL}" >"${CODEX_CONFIG_TEMP}"
    if [ -f "${CODEX_CONFIG_FILE}" ]; then
        sed '/^[[:space:]]*openai_base_url[[:space:]]*=/d' \
            "${CODEX_CONFIG_FILE}" >>"${CODEX_CONFIG_TEMP}"
    fi
    chmod 600 "${CODEX_CONFIG_TEMP}"
    mv "${CODEX_CONFIG_TEMP}" "${CODEX_CONFIG_FILE}"

    if ! printf '%s\n' "${CODEX_TOKEN}" | \
        "${MISE_COMMAND}" exec -- "${CLI_COMMAND}" login --with-api-key; then
        err "Failed to save Codex API token"
        return 1
    fi

    suc "Codex API configuration saved"
}

if ! is_valid_npm_registry "${NPM_REGISTRY}"; then
    err "NPM_REGISTRY must be an http:// or https:// URL"
    exit 1
fi

if ! find_mise; then
    err "mise is required to install Codex CLI"
    exit 1
fi

if "${MISE_COMMAND}" exec -- sh -c "command -v ${CLI_COMMAND} >/dev/null 2>&1"; then
    info "Codex CLI is already installed, skip"
else
    info "Installing ${CLI_PACKAGE}"
    if ! install_cli; then
        err "Failed to install Codex CLI"
        exit 1
    fi
fi

if ! "${MISE_COMMAND}" exec -- "${CLI_COMMAND}" --version; then
    err "Codex CLI installation verification failed"
    exit 1
fi

if ! configure_codex; then
    exit 1
fi

suc "Codex CLI is ready"
