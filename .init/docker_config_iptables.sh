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

# ====================================
# 验证函数
# ====================================

# 验证 IPv4 地址格式
validate_ipv4() {
    addr="$1"

    # 检查 CIDR 格式
    case "$addr" in
        */*)
            prefix="${addr#*/}"
            ip_part="${addr%/*}"
            # 前缀必须是 0-32 的数字
            case "$prefix" in
                ''|*[!0-9]*) return 1 ;;
                *) [ "$prefix" -le 32 ] 2>/dev/null || return 1 ;;
            esac
            addr="$ip_part"
            ;;
    esac

    # 验证 IPv4 格式 (x.x.x.x)
    echo "$addr" | awk -F. '{
        if (NF != 4) exit 1
        for (i = 1; i <= 4; i++) {
            if ($i < 0 || $i > 255) exit 1
            if ($i ~ /^0/ && length($i) > 1) exit 1
        }
    }'
}

# 验证 IPv6 地址格式
validate_ipv6() {
    addr="$1"

    # 检查 CIDR 格式
    case "$addr" in
        */*)
            prefix="${addr#*/}"
            ip_part="${addr%/*}"
            # 前缀必须是 0-128 的数字
            case "$prefix" in
                ''|*[!0-9]*) return 1 ;;
                *) [ "$prefix" -le 128 ] 2>/dev/null || return 1 ;;
            esac
            addr="$ip_part"
            ;;
    esac

    # 简单验证：必须包含冒号且为十六进制
    echo "$addr" | grep -qE '^[0-9a-fA-F:]+$'
}

# 验证端口号
validate_port() {
    port="$1"

    case "$port" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] ;;
    esac
}

# 验证协议类型
validate_proto() {
    proto="$1"

    case "$proto" in
        tcp|udp|icmp) return 0 ;;
        *) return 1 ;;
    esac
}

# ====================================
# 链管理
# ====================================

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

# ====================================
# 规则应用
# ====================================

apply_family() {
    family="$1"
    cmd="$2"
    managed=""
    line_num=0

    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    ensure_chain "$cmd"
    "$cmd" -A "$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

    if [ -f "$CONFIG" ]; then
        while IFS=' ' read -r rule_family source port proto extra; do
            line_num=$((line_num + 1))

            # 跳过空行和注释
            case "${rule_family:-}" in
                ''|'#'*) continue ;;
            esac

            # 跳过缺少必要字段的行
            [ -n "${source:-}" ] || continue
            [ -n "${port:-}" ] || continue
            [ -z "${extra:-}" ] || continue

            # 跳过协议族不匹配的行
            if [ "$rule_family" != "$family" ]; then
                continue
            fi

            # 验证配置
            proto="${proto:-tcp}"

            if [ "$family" = "ipv4" ]; then
                if ! validate_ipv4 "$source"; then
                    echo "[W] Line $line_num: Invalid IPv4 address: $source" >&2
                    continue
                fi
            else
                if ! validate_ipv6 "$source"; then
                    echo "[W] Line $line_num: Invalid IPv6 address: $source" >&2
                    continue
                fi
            fi

            if ! validate_port "$port"; then
                echo "[W] Line $line_num: Invalid port: $port (must be 1-65535)" >&2
                continue
            fi

            if ! validate_proto "$proto"; then
                echo "[W] Line $line_num: Invalid protocol: $proto (must be tcp/udp/icmp)" >&2
                continue
            fi

            # 应用规则
            "$cmd" -A "$CHAIN" -p "$proto" -s "$source" --dport "$port" -j RETURN

            # 记录管理的端口
            key="$proto:$port"
            case " $managed " in
                *" $key "*) ;;
                *) managed="$managed $key" ;;
            esac
        done < "$CONFIG"
    fi

    # 为管理的端口添加 DROP 规则
    for key in $managed; do
        proto="${key%%:*}"
        port="${key#*:}"
        "$cmd" -A "$CHAIN" -p "$proto" --dport "$port" -j DROP
    done

    "$cmd" -A "$CHAIN" -j RETURN
}

# ====================================
# IPv6 支持检测
# ====================================

is_ipv6_enabled() {
    # 检查1: /proc/net/if_inet6 文件存在
    if [ ! -f /proc/net/if_inet6 ]; then
        return 1
    fi

    # 检查2: IPv6 未被 sysctl 禁用
    if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = "1" ]; then
            return 1
        fi
    fi

    return 0
}

# ====================================
# 主流程
# ====================================

# 应用 IPv4 规则
apply_family ipv4 iptables

# 应用 IPv6 规则（仅当系统支持时）
if is_ipv6_enabled; then
    apply_family ipv6 ip6tables
fi
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
# ====================================
# Docker 端口白名单配置文件
# ====================================
#
# 格式: 协议族 源地址 端口 协议
#
# 字段说明：
#   协议族: ipv4 或 ipv6
#   源地址: IP 地址或 CIDR 格式（如 192.168.1.0/24）
#   端口:   1-65535 之间的端口号
#   协议:   tcp（默认）| udp | icmp
#
# 注意事项：
#   - 配置错误会被跳过并记录警告
#   - 未列出的端口将被拒绝访问
#   - Docker 容器之间的通信不受影响
#   - 修改配置后重启 Docker 生效
#
# ====================================
# IPv4 示例
# ====================================

# 允许单个 IP 访问 HTTPS
# ipv4 1.2.3.4/32 443 tcp

# 允许内网段访问 HTTP
# ipv4 10.0.0.0/8 80 tcp
# ipv4 172.16.0.0/12 80 tcp
# ipv4 192.168.0.0/16 80 tcp

# 允许办公网段访问 SSH
# ipv4 203.0.113.0/24 22 tcp

# 允许特定 IP 访问数据库端口
# ipv4 198.51.100.10/32 3306 tcp
# ipv4 198.51.100.10/32 5432 tcp

# ====================================
# IPv6 示例（需要系统支持 IPv6）
# ====================================

# 允许 IPv6 地址访问 HTTPS
# ipv6 2001:db8::1/128 443 tcp

# 允许 IPv6 网段访问 HTTP
# ipv6 2001:db8::/32 80 tcp

# ====================================
# UDP 协议示例
# ====================================

# 允许 DNS 查询
# ipv4 198.51.100.0/24 53 udp

# ====================================
# 常见服务端口参考
# ====================================
# HTTP: 80
# HTTPS: 443
# SSH: 22
# FTP: 21
# SMTP: 25
# DNS: 53
# MySQL: 3306
# PostgreSQL: 5432
# MongoDB: 27017
# Redis: 6379
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
