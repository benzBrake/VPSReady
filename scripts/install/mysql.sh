#!/usr/bin/env sh

set -e

# Install MySQL with Docker Compose and print the root password.

SCRIPT_DIR=$(dirname "$(readlink -f "${0}")")
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] ${*}" >&2; }
    err() { echo "[E] ${*}" >&2; }
    suc() { echo "[S] ${*}" >&2; }
fi

MYSQL_CONTAINER_NAME=${MYSQL_CONTAINER_NAME:-mysql}
MYSQL_IMAGE=${MYSQL_IMAGE:-mysql:latest}
MYSQL_DATA_DIR=${MYSQL_DATA_DIR:-/data/mysql}
MYSQL_COMPOSE_FILE=${MYSQL_COMPOSE_FILE:-${MYSQL_DATA_DIR}/docker-compose.yml}
MYSQL_ENV_FILE=${MYSQL_ENV_FILE:-${MYSQL_DATA_DIR}/.env}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_PROFILE_FILE=${MYSQL_PROFILE_FILE:-/data/.profile}

if ! command -v docker >/dev/null 2>&1; then
    info "Docker is not installed; skip MySQL installation"
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is unavailable; skip MySQL installation"
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    COMPOSE_TYPE=docker
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    COMPOSE_TYPE=legacy
else
    err "Docker Compose is unavailable; skip MySQL installation"
    exit 1
fi

generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
        return "${?}"
    fi

    if command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1; then
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
        return "${?}"
    fi

    err "Cannot generate a secure MySQL root password; install openssl"
    return 1
}

validate_configuration() {
    case "${MYSQL_CONTAINER_NAME}" in
        ""|*[!A-Za-z0-9_.-]*)
            err "MYSQL_CONTAINER_NAME contains unsupported characters"
            return 1
            ;;
    esac

    case "${MYSQL_IMAGE}" in
        ""|*[!A-Za-z0-9./:@_-]*)
            err "MYSQL_IMAGE contains unsupported characters"
            return 1
            ;;
    esac

    case "${MYSQL_PORT}" in
        ""|*[!0-9]*)
            err "MYSQL_PORT must be a number between 1 and 65535"
            return 1
            ;;
    esac

    if [ "${MYSQL_PORT}" -lt 1 ] || [ "${MYSQL_PORT}" -gt 65535 ]; then
        err "MYSQL_PORT must be a number between 1 and 65535"
        return 1
    fi
}

if ! validate_configuration; then
    exit 1
fi

mkdir -p "${MYSQL_DATA_DIR}/data"

if [ -s "${MYSQL_ENV_FILE}" ]; then
    MYSQL_ROOT_PASSWORD=$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' "${MYSQL_ENV_FILE}" | sed -n '1p')
elif [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
    MYSQL_ROOT_PASSWORD=$(generate_password)
fi

if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    err "MYSQL_ROOT_PASSWORD is empty"
    exit 1
fi

printf '%s\n' \
    "MYSQL_IMAGE=${MYSQL_IMAGE}" \
    "MYSQL_CONTAINER_NAME=${MYSQL_CONTAINER_NAME}" \
    "MYSQL_PORT=${MYSQL_PORT}" \
    "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
    > "${MYSQL_ENV_FILE}"
chmod 600 "${MYSQL_ENV_FILE}"

tee "${MYSQL_COMPOSE_FILE}" >/dev/null <<'EOF'
services:
    mysql:
        image: ${MYSQL_IMAGE}
        container_name: ${MYSQL_CONTAINER_NAME}
        restart: unless-stopped
        environment:
            MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
        ports:
            - "127.0.0.1:${MYSQL_PORT}:3306"
        volumes:
            - ./data:/var/lib/mysql
EOF

run_compose() {
    if [ "${COMPOSE_TYPE}" = docker ]; then
        docker compose -f "${MYSQL_COMPOSE_FILE}" --env-file "${MYSQL_ENV_FILE}" up -d
        return "${?}"
    fi

    (
        cd "${MYSQL_DATA_DIR}"
        docker-compose -f "$(basename "${MYSQL_COMPOSE_FILE}")" up -d
    )
}

shell_quote() {
    printf '%s' "${1}" | sed "s/'/'\\\\''/g"
}

configure_mysql_profile() {
    MYSQL_PROFILE_START='# VPSReady MySQL login function begin'
    MYSQL_PROFILE_END='# VPSReady MySQL login function end'
    MYSQL_PROFILE_ENV_FILE_QUOTED=$(shell_quote "${MYSQL_ENV_FILE}")
    MYSQL_PROFILE_PORT_QUOTED=$(shell_quote "${MYSQL_PORT}")
    MYSQL_PROFILE_DIR=$(dirname "${MYSQL_PROFILE_FILE}")
    if ! mkdir -p "${MYSQL_PROFILE_DIR}"; then
        err "Failed to create ${MYSQL_PROFILE_DIR}"
        return 1
    fi
    MYSQL_PROFILE_TEMP_FILE=$(mktemp "${MYSQL_PROFILE_FILE}.XXXXXX")

    if [ -f "${MYSQL_PROFILE_FILE}" ]; then
        awk -v start="${MYSQL_PROFILE_START}" -v end="${MYSQL_PROFILE_END}" '
            $0 == start { skip = 1; next }
            $0 == end { skip = 0; next }
            !skip { print }
        ' "${MYSQL_PROFILE_FILE}" >"${MYSQL_PROFILE_TEMP_FILE}"
    fi

    printf '%s\n' \
        "${MYSQL_PROFILE_START}" \
        'mysql() (' \
        '    MYSQL_PROFILE_ENV_FILE='"'${MYSQL_PROFILE_ENV_FILE_QUOTED}'" \
        '    MYSQL_PROFILE_PASSWORD=$(sed -n '\''s/^MYSQL_ROOT_PASSWORD=//p'\'' "${MYSQL_PROFILE_ENV_FILE}" | sed -n '\''1p'\'')' \
        '    if [ -z "${MYSQL_PROFILE_PASSWORD}" ]; then' \
        '        echo "MySQL root password is missing from ${MYSQL_PROFILE_ENV_FILE}" >&2' \
        '        return 1' \
        '    fi' \
        '    if ! command -v mysql >/dev/null 2>&1; then' \
        '        echo "MySQL client is not installed" >&2' \
        '        return 1' \
        '    fi' \
        '    MYSQL_PWD="${MYSQL_PROFILE_PASSWORD}" mysql -h 127.0.0.1 -P '"${MYSQL_PROFILE_PORT_QUOTED}"' -u root "${@}"' \
        ')' \
        "${MYSQL_PROFILE_END}" >>"${MYSQL_PROFILE_TEMP_FILE}"

    if ! mv "${MYSQL_PROFILE_TEMP_FILE}" "${MYSQL_PROFILE_FILE}"; then
        rm -f "${MYSQL_PROFILE_TEMP_FILE}"
        err "Failed to update ${MYSQL_PROFILE_FILE}"
        return 1
    fi
}

info "Starting MySQL Compose project in ${MYSQL_DATA_DIR}"
run_compose

suc "MySQL container started"
configure_mysql_profile
suc "MySQL login function written to ${MYSQL_PROFILE_FILE}"
printf 'MySQL root password: %s\n' "${MYSQL_ROOT_PASSWORD}"
printf 'MySQL connection: 127.0.0.1:%s (container: %s)\n' "${MYSQL_PORT}" "${MYSQL_CONTAINER_NAME}"
