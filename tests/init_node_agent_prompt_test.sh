#!/usr/bin/env sh
# Verify that Agent CLI prompts are conditional and independent.

set -eu

ROOT_DIR=$(cd "$(dirname "${0}")/.." && pwd)
FUNCTIONS_FILE=$(mktemp)

cleanup() {
    rm -f "${FUNCTIONS_FILE}"
}

trap cleanup EXIT HUP INT TERM

sed -n '/^is_valid_mirror()/,/^}/p' "${ROOT_DIR}/init.sh" >"${FUNCTIONS_FILE}"
sed -n '/^is_valid_agent_token()/,/^}/p' "${ROOT_DIR}/init.sh" >>"${FUNCTIONS_FILE}"
sed -n '/^prompt_agent_configuration()/,/^}/p' "${ROOT_DIR}/init.sh" >>"${FUNCTIONS_FILE}"
sed -n '/^prompt_node_agent_clis()/,/^}/p' "${ROOT_DIR}/init.sh" >>"${FUNCTIONS_FILE}"
sed -n '/^prompt_mirror_acceleration()/,/^}/p' "${ROOT_DIR}/init.sh" >>"${FUNCTIONS_FILE}"
. "${FUNCTIONS_FILE}"

grep -F \
    'NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"' \
    "${ROOT_DIR}/init.sh" >/dev/null

PROMPT_CALLS=""
PROMPT_SEQUENCE=""
prompt_yes_no() {
    PROMPT_CALLS="${PROMPT_CALLS}${PROMPT_CALLS:+|}${1}"
    PROMPT_VALUE="${PROMPT_SEQUENCE%% *}"
    if [ "${PROMPT_SEQUENCE}" = "${PROMPT_VALUE}" ]; then
        PROMPT_SEQUENCE=""
    else
        PROMPT_SEQUENCE="${PROMPT_SEQUENCE#* }"
    fi
}

PROMPT_VALUE_SEQUENCE=""
SECRET_PROMPT_CALLS=0
SECRET_PROMPT_VALUE=""
prompt_value() {
    case "${PROMPT_VALUE_SEQUENCE}" in
        *'|'*)
            PROMPT_VALUE="${PROMPT_VALUE_SEQUENCE%%|*}"
            PROMPT_VALUE_SEQUENCE="${PROMPT_VALUE_SEQUENCE#*|}"
            ;;
        *)
            PROMPT_VALUE="${PROMPT_VALUE_SEQUENCE}"
            PROMPT_VALUE_SEQUENCE=""
            ;;
    esac
}
prompt_secret() {
    SECRET_PROMPT_CALLS=$((SECRET_PROMPT_CALLS + 1))
    PROMPT_VALUE="${SECRET_PROMPT_VALUE}"
}
warn() {
    :
}

MIRROR_PROMPT_CALLS=""
prompt_mirror() {
    MIRROR_PROMPT_CALLS="${MIRROR_PROMPT_CALLS}${MIRROR_PROMPT_CALLS:+|}GitHub"
}
prompt_npm_registry() {
    MIRROR_PROMPT_CALLS="${MIRROR_PROMPT_CALLS}${MIRROR_PROMPT_CALLS:+|}npm"
}

PROMPT_SEQUENCE="false"
MIRROR_ACCELERATION=false
MIRROR="https://mirror.example.test"
NPM_REGISTRY="https://registry.npmmirror.com"
DOCKER_REGION=cn
DOCKER_INSTALL_MIRROR=Aliyun
DOCKER_REGISTRY_MIRROR="https://docker.example.test"
prompt_mirror_acceleration
[ "${MIRROR_PROMPT_CALLS}" = "" ]
[ "${MIRROR}" = "" ]
[ "${NPM_REGISTRY}" = "https://registry.npmjs.org" ]
[ "${DOCKER_REGION}" = global ]
[ "${DOCKER_INSTALL_MIRROR}" = "" ]
[ "${DOCKER_REGISTRY_MIRROR+x}" != x ]

PROMPT_SEQUENCE="true"
MIRROR_PROMPT_CALLS=""
prompt_mirror_acceleration
[ "${MIRROR_PROMPT_CALLS}" = "GitHub|npm" ]
PROMPT_CALLS=""

prompt_agent_configuration "Codex" ""
[ "${SECRET_PROMPT_CALLS}" -eq 0 ]
[ "${CONFIGURED_AGENT_BASE_URL}" = "" ]
[ "${CONFIGURED_AGENT_TOKEN}" = "" ]

PROMPT_VALUE_SEQUENCE="https://codex.example.test/v1"
SECRET_PROMPT_CALLS=0
SECRET_PROMPT_VALUE="codex-test-token"
prompt_agent_configuration "Codex" ""
[ "${SECRET_PROMPT_CALLS}" -eq 1 ]
[ "${CONFIGURED_AGENT_BASE_URL}" = 'https://codex.example.test/v1' ]
[ "${CONFIGURED_AGENT_TOKEN}" = 'codex-test-token' ]

AGENT_CONFIG_CALLS=""
prompt_agent_configuration() {
    AGENT_CONFIG_CALLS="${AGENT_CONFIG_CALLS}${AGENT_CONFIG_CALLS:+|}${1}"
    CONFIGURED_AGENT_BASE_URL="https://config.example.test"
    CONFIGURED_AGENT_TOKEN="test-token"
}

INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true
INSTALL_MISE=false
CODEX_BASE_URL="stale"
CODEX_TOKEN="stale"
CLAUDE_BASE_URL="stale"
CLAUDE_TOKEN="stale"
prompt_node_agent_clis
[ "${PROMPT_CALLS}" = "" ]
[ "${AGENT_CONFIG_CALLS}" = "" ]
[ "${INSTALL_CODEX}" = false ]
[ "${INSTALL_CLAUDE_CODE}" = false ]
[ "${CODEX_BASE_URL}" = "" ]
[ "${CODEX_TOKEN}" = "" ]
[ "${CLAUDE_BASE_URL}" = "" ]
[ "${CLAUDE_TOKEN}" = "" ]

PROMPT_CALLS=""
PROMPT_SEQUENCE="false true"
AGENT_CONFIG_CALLS=""
INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true
INSTALL_MISE=true
prompt_node_agent_clis
[ "${PROMPT_CALLS}" = 'Install Codex CLI|Install Claude Code CLI' ]
[ "${AGENT_CONFIG_CALLS}" = 'Claude Code' ]
[ "${INSTALL_CODEX}" = false ]
[ "${INSTALL_CLAUDE_CODE}" = true ]
[ "${CODEX_BASE_URL}" = "" ]
[ "${CODEX_TOKEN}" = "" ]
[ "${CLAUDE_BASE_URL}" = 'https://config.example.test' ]
[ "${CLAUDE_TOKEN}" = 'test-token' ]

printf '%s\n' 'Node.js Agent CLI prompt tests passed'
