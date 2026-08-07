#!/usr/bin/env sh
# Verify Web server selection helpers without running system initialization.

set -eu

ROOT_DIR=$(cd "$(dirname "${0}")/.." && pwd)
FUNCTIONS_FILE=$(mktemp)

cleanup() {
    rm -f "${FUNCTIONS_FILE}"
}

trap cleanup EXIT HUP INT TERM

sed -n '/^is_valid_web_server()/,/^}/p' "${ROOT_DIR}/init.sh" > "${FUNCTIONS_FILE}"
sed -n '/^prompt_web_server()/,/^}/p' "${ROOT_DIR}/init.sh" >> "${FUNCTIONS_FILE}"
sed -n '/^warn_web_server_conflicts()/,/^}/p' "${ROOT_DIR}/init.sh" >> "${FUNCTIONS_FILE}"
sed -n '/^install_web_server()/,/^}/p' "${ROOT_DIR}/init.sh" >> "${FUNCTIONS_FILE}"

. "${FUNCTIONS_FILE}"

is_valid_web_server nginx
is_valid_web_server caddy
is_valid_web_server none
if is_valid_web_server apache; then
    printf '%s\n' 'Invalid Web server was accepted' >&2
    exit 1
fi

PROMPT_SEQUENCE='invalid CADDY'
PROMPT_WARNED=false
prompt_value() {
    case "${PROMPT_SEQUENCE}" in
        *" "*)
            PROMPT_VALUE="${PROMPT_SEQUENCE%% *}"
            PROMPT_SEQUENCE="${PROMPT_SEQUENCE#* }"
            ;;
        *)
            PROMPT_VALUE="${PROMPT_SEQUENCE}"
            ;;
    esac
}
warn() {
    PROMPT_WARNED=true
}

WEB_SERVER=nginx
prompt_web_server
[ "${WEB_SERVER}" = caddy ]
[ "${PROMPT_WARNED}" = true ]

CONFLICT_WARNING=false
caddy() {
    return 0
}
warn() {
    CONFLICT_WARNING=true
}

warn_web_server_conflicts nginx
[ "${CONFLICT_WARNING}" = true ]

INSTALL_LOG=""
info() {
    INSTALL_LOG="${INSTALL_LOG}${INSTALL_LOG:+ }${1}"
}
warn_web_server_conflicts() {
    INSTALL_LOG="${INSTALL_LOG}${INSTALL_LOG:+ }conflict-check"
}

WEB_SERVER=none
install_web_server
[ "${INSTALL_LOG}" = 'Skip Web server' ]

grep -F 'warn_web_server_conflicts nginx' "${ROOT_DIR}/init.sh" >/dev/null
grep -F '/data/scripts/install/nginx.sh' "${ROOT_DIR}/init.sh" >/dev/null
grep -F 'warn_web_server_conflicts caddy' "${ROOT_DIR}/init.sh" >/dev/null
grep -F '/data/scripts/install/caddy.sh' "${ROOT_DIR}/init.sh" >/dev/null

printf '%s\n' 'Web server selection tests passed'
