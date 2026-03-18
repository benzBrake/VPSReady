#!/bin/sh
# Caddy 安装脚本

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
CADDY_REPO="${CADDY_REPO:-lxhao61/integrated-examples}"
CADDY_INSTALL_DIR="${CADDY_INSTALL_DIR:-/usr/local/bin}"
CADDY_CONFIG_DIR="${CADDY_CONFIG_DIR:-/etc/caddy}"
CADDY_DATA_DIR="${CADDY_DATA_DIR:-/data/caddy}"
DOWNLOAD_URL="${DOWNLOAD_URL:-}"
ARCH="${ARCH:-}"
CADDY_OS="${CADDY_OS:-}"

# ====================================
# 检测系统架构
# ====================================
detect_arch() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            err "Unsupported architecture: ${ARCH}"
            return 1
            ;;
    esac
    info "Detected architecture: ${ARCH}"
    return 0
}

# ====================================
# 检测操作系统
# ====================================
detect_os() {
    CADDY_OS=$(uname -s)
    case "${CADDY_OS}" in
        Linux)
            CADDY_OS="linux"
            ;;
        Darwin)
            CADDY_OS="darwin"
            ;;
        *)
            err "Unsupported OS: ${CADDY_OS}"
            return 1
            ;;
    esac
    info "Detected OS: ${CADDY_OS}"
    return 0
}

# ====================================
# 获取最新 Release 版本
# ====================================
get_latest_release() {
    info "Fetching latest release from ${CADDY_REPO}..."

    # 尝试使用 GitHub API 获取最新 release
    LATEST_RELEASE=$(curl -fsSL "https://api.github.com/repos/${CADDY_REPO}/releases/latest" 2>/dev/null)

    if [ -z "${LATEST_RELEASE}" ]; then
        err "Failed to fetch release information"
        return 1
    fi

    # 提取 tag_name
    CADDY_VERSION=$(echo "${LATEST_RELEASE}" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"?([^,"]*)"?.*/\1/')

    if [ -z "${CADDY_VERSION}" ]; then
        err "Failed to extract version from release"
        return 1
    fi

    suc "Found latest version: ${CADDY_VERSION}"
    return 0
}

# ====================================
# 构建下载 URL
# ====================================
build_download_url() {
    info "Building download URL..."

    # 如果用户指定了下载 URL，直接使用
    if [ -n "${DOWNLOAD_URL}" ]; then
        info "Using custom download URL: ${DOWNLOAD_URL}"
        return 0
    fi

    # 自动构建 URL
    # 格式: https://github.com/lxhao61/integrated-examples/releases/download/{version}/caddy-{os}-{arch}.tar.gz
    DOWNLOAD_URL="https://github.com/${CADDY_REPO}/releases/download/${CADDY_VERSION}/caddy-${CADDY_OS}-${ARCH}.tar.gz"

    # 验证 URL 是否可访问
    if ! curl -fsSL -I "${DOWNLOAD_URL}" >/dev/null 2>&1; then
        warn "Primary URL not accessible, trying mirror..."

        # 尝试使用 jsDelivr CDN
        DOWNLOAD_URL="https://cdn.jsdelivr.net/gh/${CADDY_REPO}@${CADDY_VERSION}/caddy_${CADDY_OS}_${ARCH}"

        if ! curl -fsSL -I "${DOWNLOAD_URL}" >/dev/null 2>&1; then
            err "Failed to find accessible download URL"
            return 1
        fi
    fi

    suc "Download URL: ${DOWNLOAD_URL}"
    return 0
}

# ====================================
# 下载 Caddy 二进制文件
# ====================================
download_caddy() {
    info "Downloading Caddy from ${DOWNLOAD_URL}..."

    TEMP_DIR=$(mktemp -d)
    CADDY_TEMP="${TEMP_DIR}/caddy"
    DOWNLOAD_TEMP="${TEMP_DIR}/caddy.tar.gz"

    if ! curl -fsSL "${DOWNLOAD_URL}" -o "${DOWNLOAD_TEMP}"; then
        err "Failed to download Caddy"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    # 验证下载的文件
    if [ ! -f "${DOWNLOAD_TEMP}" ] || [ ! -s "${DOWNLOAD_TEMP}" ]; then
        err "Downloaded file is empty or not found"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    # 解压 tar.gz 文件
    if ! tar -xzf "${DOWNLOAD_TEMP}" -C "${TEMP_DIR}" 2>/dev/null; then
        err "Failed to extract Caddy from archive"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    # 清理下载的压缩包
    rm -f "${DOWNLOAD_TEMP}"

    # 验证解压后的二进制文件
    if [ ! -f "${CADDY_TEMP}" ] || [ ! -s "${CADDY_TEMP}" ]; then
        err "Extracted caddy binary not found"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    suc "Caddy downloaded successfully to ${CADDY_TEMP}"
    echo "${TEMP_DIR}"
    return 0
}

# ====================================
# 安装 Caddy
# ====================================
install_caddy() {
    TEMP_DIR=$1
    CADDY_TEMP="${TEMP_DIR}/caddy"

    info "Installing Caddy to ${CADDY_INSTALL_DIR}..."

    # 确保安装目录存在
    if [ ! -d "${CADDY_INSTALL_DIR}" ]; then
        mkdir -p "${CADDY_INSTALL_DIR}" || {
            err "Failed to create ${CADDY_INSTALL_DIR}"
            rm -rf "${TEMP_DIR}"
            return 1
        }
    fi

    # 安装二进制文件
    if ! cp -f "${CADDY_TEMP}" "${CADDY_INSTALL_DIR}/caddy"; then
        err "Failed to copy Caddy to ${CADDY_INSTALL_DIR}"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    # 设置可执行权限
    if ! chmod +x "${CADDY_INSTALL_DIR}/caddy"; then
        err "Failed to set executable permission"
        rm -rf "${TEMP_DIR}"
        return 1
    fi

    # 清理临时文件
    rm -rf "${TEMP_DIR}"

    suc "Caddy installed to ${CADDY_INSTALL_DIR}/caddy"
    return 0
}

# ====================================
# 创建 Caddy 配置目录
# ====================================
create_config_dirs() {
    info "Creating Caddy directories..."

    # 创建配置目录
    if [ ! -d "${CADDY_CONFIG_DIR}" ]; then
        mkdir -p "${CADDY_CONFIG_DIR}" || {
            warn "Failed to create ${CADDY_CONFIG_DIR}"
        }
    fi

    # 创建数据目录
    if [ ! -d "${CADDY_DATA_DIR}" ]; then
        mkdir -p "${CADDY_DATA_DIR}" || {
            warn "Failed to create ${CADDY_DATA_DIR}"
        }
    fi

    # 创建 Caddyfile 示例（如果不存在）
    if [ ! -f "${CADDY_CONFIG_DIR}/Caddyfile" ] && [ -d "${CADDY_CONFIG_DIR}" ]; then
        cat > "${CADDY_CONFIG_DIR}/Caddyfile" <<'EOF'
:80 {
    respond "Hello, World!"
}
EOF
        info "Created sample Caddyfile at ${CADDY_CONFIG_DIR}/Caddyfile"
    fi

    suc "Caddy directories ready"
    return 0
}

# ====================================
# 创建 Caddy systemd 服务
# ====================================
create_systemd_service() {
    # 检查是否使用 systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        info "systemctl not found, skipping systemd service creation"
        return 0
    fi

    info "Creating Caddy systemd service..."

    cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=${CADDY_INSTALL_DIR}/caddy run --environ --config ${CADDY_CONFIG_DIR}/Caddyfile
ExecReload=${CADDY_INSTALL_DIR}/caddy reload --config ${CADDY_CONFIG_DIR}/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 配置
    systemctl daemon-reload

    suc "Caddy systemd service created"
    return 0
}

# ====================================
# 创建 OpenRC 服务
# ====================================
create_openrc_service() {
    # 检查是否使用 OpenRC (Alpine)
    if [ ! -d /etc/init.d ] || ! command -v rc-update >/dev/null 2>&1; then
        return 0
    fi

    info "Creating Caddy OpenRC service..."

    cat > /etc/init.d/caddy <<EOF
#!/sbin/openrc-run

name="caddy"
description="Caddy Web Server"
command="${CADDY_INSTALL_DIR}/caddy"
command_args="run --environ --config ${CADDY_CONFIG_DIR}/Caddyfile"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/caddy.log"
error_log="/var/log/caddy.err"

depend() {
    need net
    after firewall
}
EOF

    chmod +x /etc/init.d/caddy

    suc "Caddy OpenRC service created"
    return 0
}

# ====================================
# 验证安装
# ====================================
verify_installation() {
    info "Verifying Caddy installation..."

    if ! command -v caddy >/dev/null 2>&1; then
        err "Caddy not found in PATH"
        return 1
    fi

    # 获取版本信息
    CADDY_VERSION=$(${CADDY_INSTALL_DIR}/caddy version 2>/dev/null | head -n 1)

    if [ -n "${CADDY_VERSION}" ]; then
        suc "Caddy installed successfully: ${CADDY_VERSION}"
    else
        suc "Caddy installed successfully"
    fi

    return 0
}

# ====================================
# 主安装流程
# ====================================
main() {
    info "Starting Caddy installation..."

    # 1. 检测系统架构和 OS
    if ! detect_arch || ! detect_os; then
        err "System detection failed"
        return 1
    fi

    # 2. 获取最新版本
    if ! get_latest_release; then
        err "Failed to get latest release version"
        return 1
    fi

    # 3. 构建下载 URL
    if ! build_download_url; then
        err "Failed to build download URL"
        return 1
    fi

    # 4. 下载 Caddy
    TEMP_DIR=$(download_caddy)
    if [ $? -ne 0 ]; then
        err "Download failed"
        return 1
    fi

    # 5. 安装 Caddy
    if ! install_caddy "${TEMP_DIR}"; then
        err "Installation failed"
        return 1
    fi

    # 6. 创建配置目录
    create_config_dirs

    # 7. 创建服务
    create_systemd_service
    create_openrc_service

    # 8. 验证安装
    verify_installation

    info "Caddy installation completed"
    info "Configuration directory: ${CADDY_CONFIG_DIR}"
    info "Start service: systemctl start caddy (systemd) or rc-service caddy start (OpenRC)"

    return 0
}

# ====================================
# 执行主流程
# ====================================
main "$@"
