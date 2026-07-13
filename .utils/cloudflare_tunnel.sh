#!/usr/bin/env sh
set -e

# Manage multiple Cloudflare Tunnel instances without changing remote tunnels.

SCRIPT_DIR=$(
    cd "$(dirname "$0")"
    pwd
)

if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    . "${SCRIPT_DIR}/common.sh"
else
    info() { echo "[I] $*" >&2; }
    warn() { echo "[W] $*" >&2; }
    err() { echo "[E] $*" >&2; }
    suc() { echo "[S] $*" >&2; }
fi

STATE_ROOT="${CF_TUNNEL_STATE_ROOT:-/data/cloudflared/tunnels}"
DOCKER_IMAGE="${CF_TUNNEL_DOCKER_IMAGE:-cloudflare/cloudflared:latest}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}"
SYSTEMD_UNIT_DIR="${CF_TUNNEL_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
OPENRC_INIT_DIR="${CF_TUNNEL_OPENRC_INIT_DIR:-/etc/init.d}"

usage() {
    cat << 'EOF'
Usage:
    cloudflare_tunnel.sh
    cloudflare_tunnel.sh add <name> [--token-file <path>]
    cloudflare_tunnel.sh remove <name> [--force]
    cloudflare_tunnel.sh list
    cloudflare_tunnel.sh start <name>
    cloudflare_tunnel.sh stop <name>
    cloudflare_tunnel.sh restart <name>
    cloudflare_tunnel.sh status [name]
    cloudflare_tunnel.sh temp <local-url>
    cloudflare_tunnel.sh help

Persistent tunnels use tokens created in the Cloudflare Zero Trust dashboard.
Removing an instance only removes local resources and never deletes the remote tunnel.
EOF
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This command must be run as root"
        return 1
    fi
}

validate_name() {
    NAME_TO_VALIDATE="$1"

    case "${NAME_TO_VALIDATE}" in
        ""|*[!a-z0-9_-]*)
            err "Invalid name: use lowercase letters, numbers, underscores, and hyphens only"
            return 1
            ;;
    esac
}

instance_dir() {
    printf '%s/%s\n' "${STATE_ROOT}" "$1"
}

container_name() {
    printf 'cloudflared-%s\n' "$1"
}

service_name() {
    printf 'cloudflared-tunnel-%s\n' "$1"
}

instance_exists() {
    [ -f "$(instance_dir "$1")/backend" ] && [ -f "$(instance_dir "$1")/token" ]
}

get_backend() {
    INSTANCE_DIR=$(instance_dir "$1")
    if [ ! -f "${INSTANCE_DIR}/backend" ]; then
        err "Tunnel instance not found: $1"
        return 1
    fi

    BACKEND=$(sed -n '1p' "${INSTANCE_DIR}/backend")
    case "${BACKEND}" in
        docker|systemd|openrc)
            printf '%s\n' "${BACKEND}"
            ;;
        *)
            err "Invalid backend metadata for tunnel: $1"
            return 1
            ;;
    esac
}

check_docker() {
    if ! docker info >/dev/null 2>&1; then
        err "Docker is installed, but the Docker daemon is unavailable"
        err "Start Docker and run the command again"
        return 1
    fi
}

detect_new_backend() {
    if command -v docker >/dev/null 2>&1; then
        check_docker || return 1
        printf 'docker\n'
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        printf 'systemd\n'
        return 0
    fi

    if command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        printf 'openrc\n'
        return 0
    fi

    err "No supported service manager found; systemd or OpenRC is required"
    return 1
}

ensure_native_cloudflared() {
    if command -v cloudflared >/dev/null 2>&1; then
        CLOUDFLARED_CMD=$(command -v cloudflared)
        return 0
    fi

    if [ ! -x "${SCRIPT_DIR}/cloudflared.sh" ]; then
        err "cloudflared installer not found: ${SCRIPT_DIR}/cloudflared.sh"
        return 1
    fi

    info "Installing cloudflared for the native service backend"
    if ! "${SCRIPT_DIR}/cloudflared.sh" --version; then
        err "Failed to install cloudflared"
        return 1
    fi

    if command -v cloudflared >/dev/null 2>&1; then
        CLOUDFLARED_CMD=$(command -v cloudflared)
    elif [ -x "${CLOUDFLARED_BIN}" ]; then
        CLOUDFLARED_CMD="${CLOUDFLARED_BIN}"
    else
        err "cloudflared is unavailable after installation"
        return 1
    fi
}

read_token() {
    TOKEN_FILE_SOURCE="${1:-}"
    TOKEN_VALUE=""

    if [ -n "${TOKEN_FILE_SOURCE}" ]; then
        if [ ! -r "${TOKEN_FILE_SOURCE}" ] || [ ! -f "${TOKEN_FILE_SOURCE}" ]; then
            err "Token file is not readable: ${TOKEN_FILE_SOURCE}"
            return 1
        fi
        TOKEN_VALUE=$(sed 's/\r$//' "${TOKEN_FILE_SOURCE}")
    else
        if [ ! -t 0 ]; then
            err "Interactive token input requires a terminal; use --token-file"
            return 1
        fi
        printf 'Tunnel token: ' >&2
        stty -echo
        trap 'stty echo; printf "\n" >&2; exit 130' INT TERM HUP
        IFS= read -r TOKEN_VALUE
        stty echo
        trap - INT TERM HUP
        printf '\n' >&2
    fi

    if [ -z "${TOKEN_VALUE}" ]; then
        err "Tunnel token cannot be empty"
        return 1
    fi

    case "${TOKEN_VALUE}" in
        *[!A-Za-z0-9._=-]*)
            err "Tunnel token contains invalid characters or multiple lines"
            return 1
            ;;
    esac
}

write_instance_state() {
    NAME="$1"
    BACKEND="$2"
    INSTANCE_DIR=$(instance_dir "${NAME}")

    umask 077
    if ! mkdir -p "${INSTANCE_DIR}"; then
        err "Failed to create state directory: ${INSTANCE_DIR}"
        return 1
    fi
    chmod 700 "${INSTANCE_DIR}"

    if ! printf '%s\n' "${TOKEN_VALUE}" > "${INSTANCE_DIR}/token"; then
        err "Failed to save tunnel token"
        return 1
    fi
    chmod 600 "${INSTANCE_DIR}/token"

    if ! printf '%s\n' "${BACKEND}" > "${INSTANCE_DIR}/backend"; then
        err "Failed to save tunnel backend"
        return 1
    fi
    chmod 600 "${INSTANCE_DIR}/backend"
}

docker_container_exists() {
    docker container inspect "$(container_name "$1")" >/dev/null 2>&1
}

docker_container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$(container_name "$1")" 2>/dev/null || true)" = "true" ]
}

docker_create() {
    NAME="$1"
    TOKEN_PATH="$(instance_dir "${NAME}")/token"
    CONTAINER_NAME=$(container_name "${NAME}")

    if docker_container_exists "${NAME}"; then
        err "Docker container already exists: ${CONTAINER_NAME}"
        return 1
    fi

    # The state token is mode 600 and owned by root on the host.
    if ! docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart unless-stopped \
        --network host \
        --user 0:0 \
        --mount "type=bind,src=${TOKEN_PATH},dst=/run/secrets/cloudflared-token,readonly" \
        "${DOCKER_IMAGE}" \
        tunnel --no-autoupdate run --token-file /run/secrets/cloudflared-token >/dev/null; then
        err "Failed to create Docker tunnel: ${NAME}"
        return 1
    fi
}

install_systemd_service() {
    NAME="$1"
    SERVICE=$(service_name "${NAME}")
    TOKEN_PATH="$(instance_dir "${NAME}")/token"
    UNIT_PATH="${SYSTEMD_UNIT_DIR}/${SERVICE}.service"

    if ! tee "${UNIT_PATH}" >/dev/null << EOF
[Unit]
Description=Cloudflare Tunnel ${NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart="${CLOUDFLARED_CMD}" tunnel --no-autoupdate run --token-file "${TOKEN_PATH}"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    then
        err "Failed to write systemd service: ${UNIT_PATH}"
        return 1
    fi

    chmod 644 "${UNIT_PATH}"
    if ! systemctl daemon-reload; then
        err "Failed to reload systemd"
        return 1
    fi
    if ! systemctl enable --now "${SERVICE}.service"; then
        err "Failed to enable or start systemd service: ${SERVICE}"
        return 1
    fi
}

install_openrc_service() {
    NAME="$1"
    SERVICE=$(service_name "${NAME}")
    TOKEN_PATH="$(instance_dir "${NAME}")/token"
    SERVICE_PATH="${OPENRC_INIT_DIR}/${SERVICE}"

    if ! tee "${SERVICE_PATH}" >/dev/null << EOF
#!/sbin/openrc-run

name="Cloudflare Tunnel ${NAME}"
description="Cloudflare Tunnel ${NAME}"
command="${CLOUDFLARED_CMD}"
command_args="tunnel --no-autoupdate run --token-file ${TOKEN_PATH}"
command_user="root:root"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0

depend() {
    need net
    after firewall
}
EOF
    then
        err "Failed to write OpenRC service: ${SERVICE_PATH}"
        return 1
    fi

    chmod 755 "${SERVICE_PATH}"
    if ! rc-update add "${SERVICE}" default; then
        err "Failed to enable OpenRC service: ${SERVICE}"
        return 1
    fi
    if ! rc-service "${SERVICE}" start; then
        err "Failed to start OpenRC service: ${SERVICE}"
        return 1
    fi
}

start_instance() {
    NAME="$1"
    validate_name "${NAME}" || return 1
    BACKEND=$(get_backend "${NAME}") || return 1

    case "${BACKEND}" in
        docker)
            check_docker || return 1
            if docker_container_exists "${NAME}"; then
                docker start "$(container_name "${NAME}")" >/dev/null
            else
                docker_create "${NAME}"
            fi
            ;;
        systemd)
            ensure_native_cloudflared || return 1
            SERVICE=$(service_name "${NAME}")
            if [ ! -f "${SYSTEMD_UNIT_DIR}/${SERVICE}.service" ]; then
                install_systemd_service "${NAME}"
            else
                systemctl enable --now "${SERVICE}.service"
            fi
            ;;
        openrc)
            ensure_native_cloudflared || return 1
            SERVICE=$(service_name "${NAME}")
            if [ ! -f "${OPENRC_INIT_DIR}/${SERVICE}" ]; then
                install_openrc_service "${NAME}"
            else
                rc-update add "${SERVICE}" default >/dev/null
                rc-service "${SERVICE}" start
            fi
            ;;
    esac

    suc "Tunnel started: ${NAME}"
}

stop_instance() {
    NAME="$1"
    validate_name "${NAME}" || return 1
    BACKEND=$(get_backend "${NAME}") || return 1

    case "${BACKEND}" in
        docker)
            check_docker || return 1
            if docker_container_running "${NAME}"; then
                docker stop "$(container_name "${NAME}")" >/dev/null
            elif ! docker_container_exists "${NAME}"; then
                warn "Docker container is already absent: $(container_name "${NAME}")"
            fi
            ;;
        systemd)
            systemctl stop "$(service_name "${NAME}").service"
            ;;
        openrc)
            rc-service "$(service_name "${NAME}")" stop
            ;;
    esac

    suc "Tunnel stopped: ${NAME}"
}

restart_instance() {
    NAME="$1"
    validate_name "${NAME}" || return 1
    BACKEND=$(get_backend "${NAME}") || return 1

    case "${BACKEND}" in
        docker)
            check_docker || return 1
            if docker_container_exists "${NAME}"; then
                docker restart "$(container_name "${NAME}")" >/dev/null
            else
                docker_create "${NAME}"
            fi
            ;;
        systemd)
            systemctl restart "$(service_name "${NAME}").service"
            ;;
        openrc)
            rc-service "$(service_name "${NAME}")" restart
            ;;
    esac

    suc "Tunnel restarted: ${NAME}"
}

status_word() {
    NAME="$1"
    BACKEND=$(get_backend "${NAME}" 2>/dev/null) || {
        printf 'invalid\n'
        return 0
    }

    case "${BACKEND}" in
        docker)
            if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
                printf 'unavailable\n'
            elif docker_container_running "${NAME}"; then
                printf 'running\n'
            elif docker_container_exists "${NAME}"; then
                printf 'stopped\n'
            else
                printf 'missing\n'
            fi
            ;;
        systemd)
            if ! command -v systemctl >/dev/null 2>&1; then
                printf 'unavailable\n'
            elif systemctl is-active --quiet "$(service_name "${NAME}").service"; then
                printf 'running\n'
            else
                printf 'stopped\n'
            fi
            ;;
        openrc)
            if ! command -v rc-service >/dev/null 2>&1; then
                printf 'unavailable\n'
            elif rc-service "$(service_name "${NAME}")" status >/dev/null 2>&1; then
                printf 'running\n'
            else
                printf 'stopped\n'
            fi
            ;;
    esac
}

list_instances() {
    FOUND=false
    printf '%-24s %-10s %s\n' "NAME" "BACKEND" "STATUS"

    if [ ! -d "${STATE_ROOT}" ]; then
        return 0
    fi

    for INSTANCE_DIR in "${STATE_ROOT}"/*; do
        [ -d "${INSTANCE_DIR}" ] || continue
        NAME=$(basename "${INSTANCE_DIR}")
        instance_exists "${NAME}" || continue
        BACKEND=$(get_backend "${NAME}" 2>/dev/null || printf 'invalid')
        STATUS=$(status_word "${NAME}")
        printf '%-24s %-10s %s\n' "${NAME}" "${BACKEND}" "${STATUS}"
        FOUND=true
    done

    if [ "${FOUND}" = false ]; then
        info "No managed tunnel instances"
    fi
}

show_status() {
    NAME="${1:-}"
    if [ -z "${NAME}" ]; then
        list_instances
        return 0
    fi

    validate_name "${NAME}" || return 1
    BACKEND=$(get_backend "${NAME}") || return 1
    STATUS=$(status_word "${NAME}")
    printf 'Name: %s\nBackend: %s\nStatus: %s\n' "${NAME}" "${BACKEND}" "${STATUS}"
}

add_instance() {
    NAME="$1"
    TOKEN_FILE_SOURCE="${2:-}"
    validate_name "${NAME}" || return 1

    if instance_exists "${NAME}"; then
        err "Tunnel instance already exists: ${NAME}"
        return 1
    fi

    BACKEND=$(detect_new_backend) || return 1
    if [ "${BACKEND}" != "docker" ]; then
        ensure_native_cloudflared || return 1
    elif docker_container_exists "${NAME}"; then
        err "Docker container already exists: $(container_name "${NAME}")"
        return 1
    fi

    read_token "${TOKEN_FILE_SOURCE}" || return 1
    write_instance_state "${NAME}" "${BACKEND}" || return 1
    TOKEN_VALUE=""
    unset TOKEN_VALUE

    case "${BACKEND}" in
        docker)
            if ! docker_create "${NAME}"; then
                warn "Local state was retained; run start ${NAME} after fixing Docker"
                return 1
            fi
            ;;
        systemd)
            if ! install_systemd_service "${NAME}"; then
                warn "Local state was retained; run start ${NAME} after fixing systemd"
                return 1
            fi
            ;;
        openrc)
            if ! install_openrc_service "${NAME}"; then
                warn "Local state was retained; run start ${NAME} after fixing OpenRC"
                return 1
            fi
            ;;
    esac

    suc "Tunnel added with ${BACKEND} backend: ${NAME}"
}

remove_systemd_service() {
    NAME="$1"
    SERVICE=$(service_name "${NAME}")
    UNIT_PATH="${SYSTEMD_UNIT_DIR}/${SERVICE}.service"

    systemctl disable --now "${SERVICE}.service" >/dev/null 2>&1 || true
    if [ -f "${UNIT_PATH}" ] && ! rm -f "${UNIT_PATH}"; then
        err "Failed to remove systemd service: ${UNIT_PATH}"
        return 1
    fi
    systemctl daemon-reload
}

remove_openrc_service() {
    NAME="$1"
    SERVICE=$(service_name "${NAME}")
    SERVICE_PATH="${OPENRC_INIT_DIR}/${SERVICE}"

    rc-service "${SERVICE}" stop >/dev/null 2>&1 || true
    rc-update del "${SERVICE}" default >/dev/null 2>&1 || true
    if [ -f "${SERVICE_PATH}" ] && ! rm -f "${SERVICE_PATH}"; then
        err "Failed to remove OpenRC service: ${SERVICE_PATH}"
        return 1
    fi
}

remove_instance() {
    NAME="$1"
    FORCE="$2"
    validate_name "${NAME}" || return 1
    BACKEND=$(get_backend "${NAME}") || return 1

    if [ "${FORCE}" != "true" ]; then
        if [ ! -t 0 ]; then
            err "Removal requires a terminal confirmation or --force"
            return 1
        fi
        printf 'Remove local tunnel instance "%s"? [y/N] ' "${NAME}" >&2
        IFS= read -r ANSWER
        case "${ANSWER}" in
            y|Y|yes|YES)
                ;;
            *)
                info "Removal cancelled"
                return 0
                ;;
        esac
    fi

    case "${BACKEND}" in
        docker)
            check_docker || return 1
            if docker_container_exists "${NAME}"; then
                docker rm -f "$(container_name "${NAME}")" >/dev/null
            fi
            ;;
        systemd)
            remove_systemd_service "${NAME}" || return 1
            ;;
        openrc)
            remove_openrc_service "${NAME}" || return 1
            ;;
    esac

    INSTANCE_DIR=$(instance_dir "${NAME}")
    if ! rm -rf "${INSTANCE_DIR}"; then
        err "Runtime was removed, but local state could not be deleted: ${INSTANCE_DIR}"
        return 1
    fi

    suc "Local tunnel instance removed: ${NAME}"
    info "The remote Cloudflare tunnel was not changed"
}

run_temp_tunnel() {
    LOCAL_URL="$1"
    case "${LOCAL_URL}" in
        http://*|https://*|tcp://*|ssh://*)
            ;;
        *)
            err "Local URL must start with http://, https://, tcp://, or ssh://"
            return 1
            ;;
    esac

    if command -v docker >/dev/null 2>&1; then
        check_docker || return 1
        exec docker run --rm "${DOCKER_IMAGE}" \
            tunnel --no-autoupdate --url "${LOCAL_URL}"
    fi

    ensure_native_cloudflared || return 1
    exec "${CLOUDFLARED_CMD}" tunnel --no-autoupdate --url "${LOCAL_URL}"
}

prompt_name() {
    printf 'Tunnel name: ' >&2
    IFS= read -r MENU_NAME
}

interactive_menu() {
    require_root || return 1

    while true; do
        cat << 'EOF'

Cloudflare Tunnel Manager
1. Add tunnel
2. Remove tunnel
3. List tunnels
4. Start tunnel
5. Stop tunnel
6. Restart tunnel
7. Show status
8. Start temporary Quick Tunnel
0. Exit
EOF
        printf 'Select: ' >&2
        IFS= read -r MENU_CHOICE

        case "${MENU_CHOICE}" in
            1)
                prompt_name
                add_instance "${MENU_NAME}" "" || true
                ;;
            2)
                prompt_name
                remove_instance "${MENU_NAME}" false || true
                ;;
            3)
                list_instances
                ;;
            4)
                prompt_name
                start_instance "${MENU_NAME}" || true
                ;;
            5)
                prompt_name
                stop_instance "${MENU_NAME}" || true
                ;;
            6)
                prompt_name
                restart_instance "${MENU_NAME}" || true
                ;;
            7)
                prompt_name
                show_status "${MENU_NAME}" || true
                ;;
            8)
                printf 'Local URL: ' >&2
                IFS= read -r MENU_URL
                run_temp_tunnel "${MENU_URL}"
                ;;
            0)
                return 0
                ;;
            *)
                warn "Invalid selection"
                ;;
        esac
    done
}

main() {
    COMMAND="${1:-}"

    if [ -z "${COMMAND}" ]; then
        interactive_menu
        return $?
    fi

    case "${COMMAND}" in
        help|-h|--help)
            usage
            ;;
        add)
            require_root || return 1
            if [ $# -lt 2 ]; then
                err "Tunnel name is required"
                usage
                return 1
            fi
            NAME="$2"
            TOKEN_FILE_SOURCE=""
            shift 2
            while [ $# -gt 0 ]; do
                case "$1" in
                    --token-file)
                        if [ $# -lt 2 ]; then
                            err "--token-file requires a path"
                            return 1
                        fi
                        TOKEN_FILE_SOURCE="$2"
                        shift 2
                        ;;
                    *)
                        err "Unknown add option: $1"
                        return 1
                        ;;
                esac
            done
            add_instance "${NAME}" "${TOKEN_FILE_SOURCE}"
            ;;
        remove)
            require_root || return 1
            if [ $# -lt 2 ] || [ $# -gt 3 ]; then
                err "Usage: $0 remove <name> [--force]"
                return 1
            fi
            FORCE=false
            if [ $# -eq 3 ]; then
                if [ "$3" != "--force" ]; then
                    err "Unknown remove option: $3"
                    return 1
                fi
                FORCE=true
            fi
            remove_instance "$2" "${FORCE}"
            ;;
        list)
            if [ $# -ne 1 ]; then
                err "Usage: $0 list"
                return 1
            fi
            list_instances
            ;;
        start|stop|restart)
            require_root || return 1
            if [ $# -ne 2 ]; then
                err "Usage: $0 ${COMMAND} <name>"
                return 1
            fi
            "${COMMAND}_instance" "$2"
            ;;
        status)
            if [ $# -gt 2 ]; then
                err "Usage: $0 status [name]"
                return 1
            fi
            show_status "${2:-}"
            ;;
        temp)
            require_root || return 1
            if [ $# -ne 2 ]; then
                err "Usage: $0 temp <local-url>"
                return 1
            fi
            run_temp_tunnel "$2"
            ;;
        *)
            err "Unknown command: ${COMMAND}"
            usage
            return 1
            ;;
    esac
}

main "$@"
