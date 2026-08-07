#!/usr/bin/env sh

# Shared Docker daemon.json configuration helpers.

if ! command -v info >/dev/null 2>&1; then
    info() { echo "[I] $*" >&2; }
    warn() { echo "[W] $*" >&2; }
    err() { echo "[E] $*" >&2; }
    suc() { echo "[S] $*" >&2; }
fi

DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE:-10m}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE:-3}
DOCKER_LOG_DRIVER=${DOCKER_LOG_DRIVER:-json-file}
DOCKER_DAEMON_JSON=${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}
DOCKER_CONFIG_BACKUP=${DOCKER_CONFIG_BACKUP:-/etc/docker/daemon.json.bak}
DOCKER_REGION=${DOCKER_REGION:-global}

DOCKER_DEFAULT_REGISTRY_MIRRORS='["https://docker.1ms.run","https://dockerproxy.net","https://proxy.vvvv.ee","https://dockerproxy.link"]'
DOCKER_MANAGE_REGISTRY=false
DOCKER_REGISTRY_MIRROR_VALUE=""

case "${DOCKER_REGION}" in
    global|cn)
        ;;
    *)
        err "DOCKER_REGION must be global or cn"
        return 1 2>/dev/null || exit 1
        ;;
esac

if [ "${DOCKER_REGISTRY_MIRROR+x}" = x ]; then
    DOCKER_MANAGE_REGISTRY=true
    if [ -n "${DOCKER_REGISTRY_MIRROR}" ]; then
        DOCKER_REGISTRY_MIRROR_VALUE="${DOCKER_REGISTRY_MIRROR}"
    else
        DOCKER_REGISTRY_MIRROR_VALUE=none
    fi
elif [ "${DOCKER_REGION}" = cn ]; then
    DOCKER_MANAGE_REGISTRY=true
    DOCKER_REGISTRY_MIRROR_VALUE=default
fi

validate_registry_mirror() {
    case "${1}" in
        http://?*|https://?*)
            ;;
        *)
            err "Invalid Docker registry mirror URL: ${1}"
            return 1
            ;;
    esac

    case "${1}" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/%-]*)
            err "Invalid characters in Docker registry mirror URL"
            return 1
            ;;
    esac
}

get_registry_mirrors_json() {
    if [ "${DOCKER_MANAGE_REGISTRY}" != true ]; then
        printf '%s' '[]'
        return 0
    fi

    if [ "${DOCKER_REGISTRY_MIRROR_VALUE}" = default ]; then
        printf '%s' "${DOCKER_DEFAULT_REGISTRY_MIRRORS}"
        return 0
    fi

    if [ "${DOCKER_REGISTRY_MIRROR_VALUE}" = none ]; then
        printf '%s' '[]'
        return 0
    fi

    validate_registry_mirror "${DOCKER_REGISTRY_MIRROR_VALUE}" || return 1
    printf '["%s"]' "${DOCKER_REGISTRY_MIRROR_VALUE}"
}

validate_json_file() {
    JSON_FILE="${1}"

    if command -v jq >/dev/null 2>&1; then
        jq empty "${JSON_FILE}" >/dev/null 2>&1
        return $?
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "${JSON_FILE}" >/dev/null 2>&1 <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    json.load(source)
PY
        return $?
    fi

    err "A JSON parser is required: install jq or python3"
    return 1
}

write_daemon_config_with_jq() {
    INPUT_FILE="${1}"
    OUTPUT_FILE="${2}"
    MIRRORS_JSON="${3}"

    if [ "${DOCKER_MANAGE_REGISTRY}" = true ]; then
        if [ "${DOCKER_REGISTRY_MIRROR_VALUE}" = none ]; then
            jq \
                --arg driver "${DOCKER_LOG_DRIVER}" \
                --arg max_size "${DOCKER_LOG_MAX_SIZE}" \
                --arg max_file "${DOCKER_LOG_MAX_FILE}" \
                '. + {"log-driver": $driver, "log-opts": ((if (."log-opts" | type) == "object" then ."log-opts" else {} end) + {"max-size": $max_size, "max-file": $max_file})} | del(."registry-mirrors")' \
                "${INPUT_FILE}" > "${OUTPUT_FILE}"
        else
            jq \
                --arg driver "${DOCKER_LOG_DRIVER}" \
                --arg max_size "${DOCKER_LOG_MAX_SIZE}" \
                --arg max_file "${DOCKER_LOG_MAX_FILE}" \
                --argjson mirrors "${MIRRORS_JSON}" \
                '. + {"log-driver": $driver, "log-opts": ((if (."log-opts" | type) == "object" then ."log-opts" else {} end) + {"max-size": $max_size, "max-file": $max_file}), "registry-mirrors": $mirrors}' \
                "${INPUT_FILE}" > "${OUTPUT_FILE}"
        fi
        return $?
    fi

    jq \
        --arg driver "${DOCKER_LOG_DRIVER}" \
        --arg max_size "${DOCKER_LOG_MAX_SIZE}" \
        --arg max_file "${DOCKER_LOG_MAX_FILE}" \
        '. + {"log-driver": $driver, "log-opts": ((if (."log-opts" | type) == "object" then ."log-opts" else {} end) + {"max-size": $max_size, "max-file": $max_file})}' \
        "${INPUT_FILE}" > "${OUTPUT_FILE}"
}

write_daemon_config_with_python() {
    INPUT_FILE="${1}"
    OUTPUT_FILE="${2}"
    MIRRORS_JSON="${3}"

    DOCKER_MANAGE_REGISTRY="${DOCKER_MANAGE_REGISTRY}" \
    DOCKER_REGISTRY_MIRROR_VALUE="${DOCKER_REGISTRY_MIRROR_VALUE}" \
    DOCKER_DEFAULT_REGISTRY_MIRRORS="${MIRRORS_JSON}" \
    DOCKER_LOG_DRIVER="${DOCKER_LOG_DRIVER}" \
    DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE}" \
    DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE}" \
    python3 - "${INPUT_FILE}" "${OUTPUT_FILE}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)

if not isinstance(config, dict):
    raise ValueError("daemon.json must contain a JSON object")

config["log-driver"] = os.environ["DOCKER_LOG_DRIVER"]
log_opts = config.get("log-opts")
if not isinstance(log_opts, dict):
    log_opts = {}
log_opts["max-size"] = os.environ["DOCKER_LOG_MAX_SIZE"]
log_opts["max-file"] = os.environ["DOCKER_LOG_MAX_FILE"]
config["log-opts"] = log_opts

if os.environ["DOCKER_MANAGE_REGISTRY"] == "true":
    if os.environ["DOCKER_REGISTRY_MIRROR_VALUE"] == "none":
        config.pop("registry-mirrors", None)
    else:
        config["registry-mirrors"] = json.loads(os.environ["DOCKER_DEFAULT_REGISTRY_MIRRORS"])

with open(sys.argv[2], "w", encoding="utf-8") as destination:
    json.dump(config, destination, indent=2)
    destination.write("\n")
PY
}

write_daemon_config() {
    INPUT_FILE="${1}"
    OUTPUT_FILE="${2}"
    MIRRORS_JSON="${3}"

    if command -v jq >/dev/null 2>&1; then
        write_daemon_config_with_jq "${INPUT_FILE}" "${OUTPUT_FILE}" "${MIRRORS_JSON}"
        return $?
    fi

    if command -v python3 >/dev/null 2>&1; then
        write_daemon_config_with_python "${INPUT_FILE}" "${OUTPUT_FILE}" "${MIRRORS_JSON}"
        return $?
    fi

    err "A JSON parser is required: install jq or python3"
    return 1
}

backup_daemon_config() {
    if [ -f "${DOCKER_DAEMON_JSON}" ]; then
        info "Backing up daemon.json to ${DOCKER_CONFIG_BACKUP}"
        cp -f "${DOCKER_DAEMON_JSON}" "${DOCKER_CONFIG_BACKUP}"
        return $?
    fi

    return 0
}

restart_docker_service() {
    info "Restarting Docker service"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files docker.service >/dev/null 2>&1 || systemctl status docker >/dev/null 2>&1; then
            systemctl restart docker && return 0
            systemctl restart docker.service && return 0
        fi
    fi

    if command -v rc-service >/dev/null 2>&1; then
        rc-service docker restart && return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service docker restart && return 0
    fi

    if [ -x /etc/init.d/docker ]; then
        /etc/init.d/docker restart && return 0
    fi

    err "Unable to restart Docker service"
    return 1
}

verify_docker_service() {
    if docker info >/dev/null 2>&1; then
        suc "Docker service is running"
        return 0
    fi

    err "Docker service is not running properly"
    return 1
}

rollback_daemon_config() {
    if [ -f "${DOCKER_CONFIG_BACKUP}" ]; then
        warn "Rolling back daemon.json from backup"
        mv -f "${DOCKER_CONFIG_BACKUP}" "${DOCKER_DAEMON_JSON}"
        restart_docker_service
        return $?
    fi

    rm -f "${DOCKER_DAEMON_JSON}"
    return 0
}

configure_docker_daemon() {
    DOCKER_DIR=$(dirname "${DOCKER_DAEMON_JSON}")
    if ! mkdir -p "${DOCKER_DIR}"; then
        err "Failed to create ${DOCKER_DIR}"
        return 1
    fi

    DOCKER_TEMP_JSON=$(mktemp "${DOCKER_DIR}/daemon.json.tmp.XXXXXX") || {
        err "Failed to create a temporary daemon.json"
        return 1
    }

    DOCKER_CONFIG_WAS_PRESENT=false
    if [ -f "${DOCKER_DAEMON_JSON}" ]; then
        DOCKER_CONFIG_WAS_PRESENT=true
        if ! validate_json_file "${DOCKER_DAEMON_JSON}"; then
            rm -f "${DOCKER_TEMP_JSON}"
            err "Existing daemon.json is invalid; refusing to overwrite it"
            return 1
        fi
        if ! backup_daemon_config; then
            rm -f "${DOCKER_TEMP_JSON}"
            err "Failed to backup daemon.json"
            return 1
        fi
        cp -f "${DOCKER_DAEMON_JSON}" "${DOCKER_TEMP_JSON}" || {
            rm -f "${DOCKER_TEMP_JSON}"
            return 1
        }
    else
        printf '%s\n' '{}' > "${DOCKER_TEMP_JSON}"
    fi

    DOCKER_MIRRORS_JSON=$(get_registry_mirrors_json) || {
        rm -f "${DOCKER_TEMP_JSON}"
        return 1
    }
    DOCKER_OUTPUT_JSON=$(mktemp "${DOCKER_DIR}/daemon.json.output.XXXXXX") || {
        rm -f "${DOCKER_TEMP_JSON}"
        return 1
    }

    if ! write_daemon_config "${DOCKER_TEMP_JSON}" "${DOCKER_OUTPUT_JSON}" "${DOCKER_MIRRORS_JSON}"; then
        rm -f "${DOCKER_TEMP_JSON}" "${DOCKER_OUTPUT_JSON}"
        err "Failed to update daemon.json"
        return 1
    fi

    if ! validate_json_file "${DOCKER_OUTPUT_JSON}"; then
        rm -f "${DOCKER_TEMP_JSON}" "${DOCKER_OUTPUT_JSON}"
        err "Generated daemon.json is invalid"
        return 1
    fi

    if ! mv -f "${DOCKER_OUTPUT_JSON}" "${DOCKER_DAEMON_JSON}"; then
        rm -f "${DOCKER_TEMP_JSON}" "${DOCKER_OUTPUT_JSON}"
        err "Failed to install daemon.json"
        return 1
    fi
    rm -f "${DOCKER_TEMP_JSON}"

    if ! restart_docker_service || ! verify_docker_service; then
        if [ "${DOCKER_CONFIG_WAS_PRESENT}" = true ]; then
            rollback_daemon_config
        else
            rm -f "${DOCKER_DAEMON_JSON}"
        fi
        return 1
    fi

    rm -f "${DOCKER_CONFIG_BACKUP}"
    suc "Docker daemon configuration completed"
    if [ "${DOCKER_MANAGE_REGISTRY}" = true ]; then
        if [ "${DOCKER_REGISTRY_MIRROR_VALUE}" = none ]; then
            suc "  - Registry mirrors: disabled"
        elif [ "${DOCKER_REGISTRY_MIRROR_VALUE}" = default ]; then
            suc "  - Registry mirrors: mainland defaults"
        else
            suc "  - Registry mirror: ${DOCKER_REGISTRY_MIRROR_VALUE}"
        fi
    fi
    return 0
}
