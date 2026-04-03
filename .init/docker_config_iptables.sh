#!/bin/sh
# Docker 端口白名单配置脚本
# 用途：在未安装 UFW 的系统中，为 Docker 配置基于 DOCKER-USER 的端口白名单

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/../.utils/common.sh" ]; then
    . "${SCRIPT_DIR}/../.utils/common.sh"
else
    info() { echo "[I] $*"; }
    warn() { echo "[W] $*"; }
    err() { echo "[E] $*"; }
    suc() { echo "[S] $*"; }
fi

SYSTEMD_DIR="/etc/systemd/system/docker.service.d"
SYSTEMD_DROPIN="${SYSTEMD_DIR}/port-whitelist.conf"
WHITELIST_SCRIPT="/usr/local/sbin/apply-docker-port-whitelist.sh"
WHITELIST_CONFIG="/etc/docker-port-whitelist.conf"

is_ufw_installed() {
    if command -v ufw >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

ensure_systemd_dropin() {
    if [ ! -d "${SYSTEMD_DIR}" ]; then
        info "Creating directory ${SYSTEMD_DIR}"
        mkdir -p "${SYSTEMD_DIR}" || {
            err "Failed to create ${SYSTEMD_DIR}"
            return 1
        }
    fi

    cat > "${SYSTEMD_DROPIN}" <<'EOF'
[Service]
ExecStartPost=/usr/local/sbin/apply-docker-port-whitelist.sh
EOF

    if [ $? -ne 0 ]; then
        err "Failed to write ${SYSTEMD_DROPIN}"
        return 1
    fi

    suc "Configured ${SYSTEMD_DROPIN}"
    return 0
}

ensure_whitelist_script() {
    cat > "${WHITELIST_SCRIPT}" <<'EOF'
#!/bin/sh
set -eu

CONFIG="/etc/docker-port-whitelist.conf"
CHAIN="DOCKER-PORT-WHITELIST"

ensure_chain() {
    cmd="$1"

    if ! "$cmd" -nL DOCKER-USER >/dev/null 2>&1; then
        "$cmd" -N DOCKER-USER >/dev/null 2>&1 || true
    fi

    "$cmd" -N "$CHAIN" >/dev/null 2>&1 || true
    "$cmd" -F "$CHAIN"

    if ! "$cmd" -C DOCKER-USER -j "$CHAIN" >/dev/null 2>&1; then
        "$cmd" -I DOCKER-USER 1 -j "$CHAIN"
    fi
}

apply_family() {
    family="$1"
    cmd="$2"
    managed=""

    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    ensure_chain "$cmd"
    "$cmd" -A "$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

    if [ -f "$CONFIG" ]; then
        while IFS=' ' read -r rule_family source port proto extra; do
            case "${rule_family:-}" in
                ''|'#'*) continue ;;
            esac

            [ -n "${source:-}" ] || continue
            [ -n "${port:-}" ] || continue
            [ -z "${extra:-}" ] || continue

            if [ "$rule_family" != "$family" ]; then
                continue
            fi

            proto="${proto:-tcp}"
            "$cmd" -A "$CHAIN" -p "$proto" -s "$source" --dport "$port" -j RETURN

            key="$proto:$port"
            case " $managed " in
                *" $key "*) ;;
                *) managed="$managed $key" ;;
            esac
        done < "$CONFIG"
    fi

    for key in $managed; do
        proto="${key%%:*}"
        port="${key#*:}"
        "$cmd" -A "$CHAIN" -p "$proto" --dport "$port" -j DROP
    done

    "$cmd" -A "$CHAIN" -j RETURN
}

apply_family ipv4 iptables
apply_family ipv6 ip6tables
EOF

    if [ $? -ne 0 ]; then
        err "Failed to write ${WHITELIST_SCRIPT}"
        return 1
    fi

    chmod 755 "${WHITELIST_SCRIPT}" || {
        err "Failed to chmod ${WHITELIST_SCRIPT}"
        return 1
    }

    suc "Configured ${WHITELIST_SCRIPT}"
    return 0
}

ensure_whitelist_config() {
    if [ -f "${WHITELIST_CONFIG}" ]; then
        info "Keep existing ${WHITELIST_CONFIG}"
        return 0
    fi

    cat > "${WHITELIST_CONFIG}" <<'EOF'
# 格式: 协议族 源地址 端口 协议
# 示例:
# ipv4 1.2.3.4/32 443 tcp
# ipv4 10.0.0.0/8 8080 tcp
# ipv6 2001:db8::/32 443 tcp
EOF

    if [ $? -ne 0 ]; then
        err "Failed to write ${WHITELIST_CONFIG}"
        return 1
    fi

    suc "Created ${WHITELIST_CONFIG}"
    return 0
}

reload_and_restart_docker() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl not found, skip Docker port whitelist drop-in"
        return 0
    fi

    if ! systemctl list-unit-files docker.service >/dev/null 2>&1 && ! systemctl status docker >/dev/null 2>&1; then
        warn "docker.service not found, skip restart"
        return 0
    fi

    if ! systemctl daemon-reload; then
        err "Failed to reload systemd daemon"
        return 1
    fi

    if systemctl restart docker; then
        suc "Docker service restarted"
        return 0
    fi

    if systemctl restart docker.service; then
        suc "Docker service restarted"
        return 0
    fi

    err "Failed to restart Docker service"
    return 1
}

configure_docker_port_whitelist() {
    info "Starting Docker port whitelist configuration"

    if is_ufw_installed; then
        info "UFW detected, skip Docker port whitelist configuration"
        return 0
    fi

    if ! ensure_systemd_dropin; then
        return 1
    fi

    if ! ensure_whitelist_script; then
        return 1
    fi

    if ! ensure_whitelist_config; then
        return 1
    fi

    if ! reload_and_restart_docker; then
        return 1
    fi

    suc "Docker port whitelist configured successfully"
    return 0
}

configure_docker_port_whitelist
exit $?
