#!/bin/sh
# Docker 安装与日志轮转配置脚本

# ====================================
# 引入通用函数库
# ====================================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/../.utils/common.sh" ]; then
    . "${SCRIPT_DIR}/../.utils/common.sh"
else
    # 如果 common.sh 不可用，定义基本日志函数
    info() { echo "[I] $*"; }
    warn() { echo "[W] $*"; }
    err() { echo "[E] $*"; }
    suc() { echo "[S] $*"; }
fi

# ====================================
# 环境变量与默认值
# ====================================
DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE:-10m}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE:-3}
DOCKER_LOG_DRIVER=${DOCKER_LOG_DRIVER:-json-file}
DOCKER_DAEMON_JSON=${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}
DOCKER_CONFIG_BACKUP=${DOCKER_CONFIG_BACKUP:-/etc/docker/daemon.json.bak}

# ====================================
# 备份现有配置
# ====================================
backup_daemon_config() {
    if [ -f "${DOCKER_DAEMON_JSON}" ]; then
        info "Backing up daemon.json to ${DOCKER_CONFIG_BACKUP}"
        if cp -f "${DOCKER_DAEMON_JSON}" "${DOCKER_CONFIG_BACKUP}"; then
            return 0
        else
            err "Failed to backup daemon.json"
            return 1
        fi
    else
        info "No existing daemon.json, no backup needed"
        return 0
    fi
}

# ====================================
# 创建新的 daemon.json 配置文件
# ====================================
create_daemon_config() {
    info "Creating new daemon.json with log rotation config"

    # 确保 /etc/docker 目录存在
    DOCKER_DIR=$(dirname "${DOCKER_DAEMON_JSON}")
    if [ ! -d "${DOCKER_DIR}" ]; then
        info "Creating directory ${DOCKER_DIR}"
        mkdir -p "${DOCKER_DIR}" || {
            err "Failed to create ${DOCKER_DIR}"
            return 1
        }
    fi

    # 写入配置文件
    cat > "${DOCKER_DAEMON_JSON}" <<EOF
{
  "log-driver": "${DOCKER_LOG_DRIVER}",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILE}"
  }
}
EOF

    if [ $? -eq 0 ]; then
        suc "Created daemon.json successfully"
        return 0
    else
        err "Failed to create daemon.json"
        return 1
    fi
}

# ====================================
# 检测并更新 log-driver 配置
# ====================================
update_log_driver() {
    if grep -q '"log-driver"' "${DOCKER_DAEMON_JSON}"; then
        info "Updating existing log-driver configuration"
        # 使用 sed 更新 log-driver 值
        sed -i 's/"log-driver":[[:space:]]*"[^"]*"/"log-driver": "'"${DOCKER_LOG_DRIVER}"'"/' "${DOCKER_DAEMON_JSON}"
        return $?
    else
        info "Adding new log-driver configuration"
        # 在最后一个 } 前添加 log-driver 配置
        sed -i 's/}$/,\n  "log-driver": "'"${DOCKER_LOG_DRIVER}"'"\n}/' "${DOCKER_DAEMON_JSON}"
        return $?
    fi
}

# ====================================
# 检测并更新 log-opts 配置
# ====================================
update_log_opts() {
    if grep -q '"log-opts"' "${DOCKER_DAEMON_JSON}"; then
        info "Updating existing log-opts configuration"

        # 更新 max-size
        if grep -q '"max-size"' "${DOCKER_DAEMON_JSON}"; then
            sed -i 's/"max-size":[[:space:]]*"[^"]*"/"max-size": "'"${DOCKER_LOG_MAX_SIZE}"'"/' "${DOCKER_DAEMON_JSON}"
        else
            # 在 log-opts 对象开头添加 max-size
            sed -i '/"log-opts":[[:space:]]*{/a\    "max-size": "'"${DOCKER_LOG_MAX_SIZE}"'",' "${DOCKER_DAEMON_JSON}"
        fi

        # 更新 max-file
        if grep -q '"max-file"' "${DOCKER_DAEMON_JSON}"; then
            sed -i 's/"max-file":[[:space:]]*"[0-9]*"/"max-file": "'"${DOCKER_LOG_MAX_FILE}"'"/' "${DOCKER_DAEMON_JSON}"
        else
            # 在 max-size 后添加 max-file
            sed -i 's/"max-size":[[:space:]]*"[^"]*"/&\n    "max-file": "'"${DOCKER_LOG_MAX_FILE}"'"/' "${DOCKER_DAEMON_JSON}"
        fi

        return $?
    else
        info "Adding new log-opts configuration"
        # 添加完整的 log-opts 对象
        sed -i 's/}$/,\n  "log-opts": {\n    "max-size": "'"${DOCKER_LOG_MAX_SIZE}"'",\n    "max-file": "'"${DOCKER_LOG_MAX_FILE}"'"\n  }\n}/' "${DOCKER_DAEMON_JSON}"
        return $?
    fi
}

# ====================================
# 合并日志配置到现有 daemon.json
# ====================================
merge_log_config() {
    info "Merging log configuration into existing daemon.json"

    # 更新 log-driver
    if ! update_log_driver; then
        err "Failed to update log-driver"
        return 1
    fi

    # 更新 log-opts
    if ! update_log_opts; then
        err "Failed to update log-opts"
        return 1
    fi

    suc "Log configuration merged successfully"
    return 0
}

# ====================================
# JSON 语法验证
# ====================================
validate_json_syntax() {
    # 简单的 JSON 语法检查
    # 1. 检查括号匹配
    OPEN_BRACES=$(grep -o '{' "${DOCKER_DAEMON_JSON}" | wc -l)
    CLOSE_BRACES=$(grep -o '}' "${DOCKER_DAEMON_JSON}" | wc -l)

    if [ "${OPEN_BRACES}" -ne "${CLOSE_BRACES}" ]; then
        err "JSON syntax error: unmatched braces"
        return 1
    fi

    # 2. 如果有 python3，使用 json.tool 验证
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m json.tool "${DOCKER_DAEMON_JSON}" >/dev/null 2>&1; then
            err "JSON syntax error: validation failed"
            return 1
        fi
    fi

    # 3. 如果有 jq，使用 jq 验证
    if command -v jq >/dev/null 2>&1; then
        if ! jq . "${DOCKER_DAEMON_JSON}" >/dev/null 2>&1; then
            err "JSON syntax error: validation failed"
            return 1
        fi
    fi

    info "JSON syntax validation passed"
    return 0
}

# ====================================
# 重启 Docker 服务
# ====================================
restart_docker_service() {
    info "Restarting Docker service"

    # 尝试使用 systemctl
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files docker.service >/dev/null 2>&1 || systemctl status docker >/dev/null 2>&1; then
            if systemctl restart docker; then
                suc "Docker service restarted (systemctl docker)"
                return 0
            fi
        fi

        if systemctl list-unit-files docker.service >/dev/null 2>&1; then
            if systemctl restart docker.service; then
                suc "Docker service restarted (systemctl docker.service)"
                return 0
            fi
        fi

        err "Failed to restart Docker with systemctl"
        return 1
    fi

    # 尝试使用 service
    if command -v service >/dev/null 2>&1; then
        if service docker restart; then
            suc "Docker service restarted (service)"
            return 0
        else
            err "Failed to restart Docker with service"
            return 1
        fi
    fi

    # 尝试使用 init.d 脚本（Alpine 等）
    if [ -f /etc/init.d/docker ]; then
        if /etc/init.d/docker restart; then
            suc "Docker service restarted (init.d)"
            return 0
        else
            err "Failed to restart Docker with init.d"
            return 1
        fi
    fi

    warn "Unable to restart Docker service (no supported method found)"
    return 1
}

# ====================================
# 验证 Docker 服务状态
# ====================================
verify_docker_service() {
    if ! docker info >/dev/null 2>&1; then
        err "Docker service is not running properly"
        return 1
    fi

    suc "Docker service is running"
    return 0
}

# ====================================
# 回滚配置
# ====================================
rollback_daemon_config() {
    if [ -f "${DOCKER_CONFIG_BACKUP}" ]; then
        warn "Rolling back daemon.json from backup"
        mv -f "${DOCKER_CONFIG_BACKUP}" "${DOCKER_DAEMON_JSON}"

        info "Restarting Docker service after rollback"
        restart_docker_service

        return $?
    else
        warn "No backup file found, cannot rollback"
        return 1
    fi
}

# ====================================
# 主配置函数
# ====================================
configure_docker_logs() {
    info "Starting Docker log rotation configuration"

    # 1. 备份现有配置
    if ! backup_daemon_config; then
        err "Backup failed, aborting configuration"
        return 1
    fi

    # 2. 检测 daemon.json 是否存在
    if [ ! -f "${DOCKER_DAEMON_JSON}" ]; then
        # 不存在：创建新配置
        if ! create_daemon_config; then
            err "Failed to create daemon.json"
            rollback_daemon_config
            return 1
        fi
    else
        # 存在：合并配置
        if ! merge_log_config; then
            err "Failed to merge log configuration"
            rollback_daemon_config
            return 1
        fi
    fi

    # 3. 验证 JSON 语法
    if ! validate_json_syntax; then
        err "JSON validation failed"
        rollback_daemon_config
        return 1
    fi

    # 4. 重启 Docker 服务
    if ! restart_docker_service; then
        err "Failed to restart Docker service"
        rollback_daemon_config
        return 1
    fi

    # 5. 验证服务状态
    if ! verify_docker_service; then
        err "Docker service verification failed"
        rollback_daemon_config
        return 1
    fi

    # 6. 清理备份文件
    if [ -f "${DOCKER_CONFIG_BACKUP}" ]; then
        info "Removing backup file"
        rm -f "${DOCKER_CONFIG_BACKUP}"
    fi

    suc "Docker log rotation configured successfully"
    suc "  - Log driver: ${DOCKER_LOG_DRIVER}"
    suc "  - Max size: ${DOCKER_LOG_MAX_SIZE}"
    suc "  - Max files: ${DOCKER_LOG_MAX_FILE}"

    return 0
}

# ====================================
# 主流程
# ====================================

# 1. 安装 Docker
info "Installing Docker..."
bash -c "$(curl -fsSL https://get.docker.com -o -)"

# 2. 安装 docker-compose（如果需要）
if [ -z "${NOT_INSTALL_DOCKER_COMPOSE}" ]; then
    info "Checking Docker Compose availability..."
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        suc "Docker Compose already available via docker compose"
    elif [ -n "$(command -v apk)" ]; then
        info "Installing docker-compose..."
        apk add --update --no-cache docker-compose
    else
        warn "docker compose is unavailable after Docker installation"
        warn "Skipping separate docker-compose package install to avoid conflicts with Docker official packages"
    fi
fi

# 3. 配置 Docker 日志轮转（如果未禁用）
if [ "${DOCKER_DISABLE_LOG_CONFIG}" != "true" ]; then
    # 等待 Docker 安装完成
    sleep 2

    # 检查 Docker 是否安装成功
    if command -v docker >/dev/null 2>&1; then
        if configure_docker_logs; then
            suc "Docker installation and log configuration completed"
        else
            warn "Docker installed but log configuration failed, continuing anyway..."
        fi
    else
        warn "Docker installation may have failed, skipping log configuration"
    fi
else
    info "Docker log configuration disabled by DOCKER_DISABLE_LOG_CONFIG"
fi

# 4. 配置 Docker 端口白名单（如果脚本存在）
if command -v docker >/dev/null 2>&1; then
    if [ -f "${SCRIPT_DIR}/docker_config_iptables.sh" ]; then
        if "${SCRIPT_DIR}/docker_config_iptables.sh"; then
            suc "Docker port whitelist configuration completed"
        else
            warn "Docker installed but port whitelist configuration failed, continuing anyway..."
        fi
    fi
fi
