#!/usr/bin/env sh

SCRIPT_DIR=$(
    cd "$(dirname "$0")"
    pwd
)

. "${SCRIPT_DIR}"/lib/common.sh

INTERACTIVE=false
CONFIGURE_SSH=true
INSTALL_RCLONE=true
INSTALL_GLOW=true
INSTALL_MISE=true
ENABLE_BBR=true
INSTALL_ACME=true

usage() {
    cat << 'EOF'
Usage: ./init.sh [-i] [-h]

Options:
  -i    Run the interactive initialization wizard
  -h    Show this help message
EOF
}

prompt_yes_no() {
    PROMPT_LABEL="${1}"
    PROMPT_DEFAULT="${2}"

    while :; do
        if [ "${PROMPT_DEFAULT}" = true ]; then
            printf '%s [Y/n]: ' "${PROMPT_LABEL}" >/dev/tty
        else
            printf '%s [y/N]: ' "${PROMPT_LABEL}" >/dev/tty
        fi

        if ! IFS= read -r PROMPT_INPUT </dev/tty; then
            warn "Interactive input closed. Initialization canceled."
            exit 1
        fi

        case "${PROMPT_INPUT}" in
            "")
                PROMPT_VALUE="${PROMPT_DEFAULT}"
                return 0
                ;;
            y|Y|yes|YES)
                PROMPT_VALUE=true
                return 0
                ;;
            n|N|no|NO)
                PROMPT_VALUE=false
                return 0
                ;;
            *)
                warn "Please answer yes or no."
                ;;
        esac
    done
}

prompt_value() {
    PROMPT_LABEL="${1}"
    PROMPT_DEFAULT="${2}"

    if [ -n "${PROMPT_DEFAULT}" ]; then
        printf '%s [%s]: ' "${PROMPT_LABEL}" "${PROMPT_DEFAULT}" >/dev/tty
    else
        printf '%s: ' "${PROMPT_LABEL}" >/dev/tty
    fi

    if ! IFS= read -r PROMPT_INPUT </dev/tty; then
        warn "Interactive input closed. Initialization canceled."
        exit 1
    fi

    if [ -z "${PROMPT_INPUT}" ]; then
        PROMPT_VALUE="${PROMPT_DEFAULT}"
    else
        PROMPT_VALUE="${PROMPT_INPUT}"
    fi
}

is_valid_mirror() {
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

is_valid_docker_region() {
    case "${1}" in
        global|cn)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_valid_docker_install_mirror() {
    case "${1}" in
        ""|Aliyun|AzureChinaCloud)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_valid_docker_registry_mirror() {
    case "${1}" in
        ""|none)
            return 0
            ;;
        *)
            is_valid_mirror "${1}"
            return $?
            ;;
    esac
}

is_valid_timezone() {
    case "${1}" in
        ""|/*|*".."*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+/-]*)
            return 1
            ;;
    esac

    if [ -f "/usr/share/zoneinfo/${1}" ]; then
        return 0
    fi

    if [ -f /usr/share/zoneinfo/zone.tab ] || [ -f /usr/share/zoneinfo/zone1970.tab ]; then
        return 1
    fi

    return 0
}

is_valid_email() {
    printf '%s\n' "${1}" | grep -Eq '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
}

is_valid_ssh_key() {
    case "${1}" in
        ssh-rsa\ *|ssh-ed25519\ *|ecdsa-sha2-*\ *|sk-ssh-*\ *)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_mirror() {
    while :; do
        prompt_value "GitHub mirror URL (blank for direct GitHub)" "${MIRROR}"
        if is_valid_mirror "${PROMPT_VALUE}"; then
            MIRROR="${PROMPT_VALUE}"
            return 0
        fi

        warn "Enter an empty value or an http:// or https:// mirror URL."
    done
}

prompt_docker_region() {
    while :; do
        prompt_value "Docker region (global/cn)" "${DOCKER_REGION}"
        if is_valid_docker_region "${PROMPT_VALUE}"; then
            DOCKER_REGION="${PROMPT_VALUE}"
            break
        fi

        warn "Docker region must be global or cn."
    done

    if [ "${DOCKER_REGION}" = cn ]; then
        while :; do
            prompt_value "Docker CE mirror (Aliyun/AzureChinaCloud)" "${DOCKER_INSTALL_MIRROR:-Aliyun}"
            if is_valid_docker_install_mirror "${PROMPT_VALUE}" && [ -n "${PROMPT_VALUE}" ]; then
                DOCKER_INSTALL_MIRROR="${PROMPT_VALUE}"
                return 0
            fi

            warn "Docker CE mirror must be Aliyun or AzureChinaCloud."
        done
    fi

    return 0
}

prompt_timezone() {
    while :; do
        prompt_value "Timezone" "${TIMEZONE}"
        if is_valid_timezone "${PROMPT_VALUE}"; then
            TIMEZONE="${PROMPT_VALUE}"
            return 0
        fi

        warn "Timezone must exist below /usr/share/zoneinfo, for example Asia/Shanghai."
    done
}

prompt_email() {
    while :; do
        prompt_value "Let's Encrypt account email" "${LET_MAIL}"
        if is_valid_email "${PROMPT_VALUE}"; then
            LET_MAIL="${PROMPT_VALUE}"
            return 0
        fi

        warn "Enter a valid non-empty email address."
    done
}

prompt_ssh_key() {
    while :; do
        prompt_value "SSH public key (blank keeps the default or bundled key)" "${SSHKEY}"
        if [ -z "${PROMPT_VALUE}" ] || is_valid_ssh_key "${PROMPT_VALUE}"; then
            SSHKEY="${PROMPT_VALUE}"
            return 0
        fi

        warn "Enter a supported OpenSSH public key or leave the value blank."
    done
}

print_summary() {
    printf '\nInitialization summary:\n' >/dev/tty
    printf '  Timezone: %s\n' "${TIMEZONE}" >/dev/tty
    printf '  GitHub mirror: %s\n' "${MIRROR:-direct GitHub}" >/dev/tty
    printf '  SSH hardening: %s\n' "${CONFIGURE_SSH}" >/dev/tty
    if [ "${CONFIGURE_SSH}" = true ]; then
        printf '    Installs/updates a public key, disables password login, and can set port 33022.\n' >/dev/tty
        printf '    Install/update SSH public key: %s\n' "${INSTALL_SSH_KEY}" >/dev/tty
        printf '    Change SSH port to 33022: %s\n' "${CHANGE_SSH_PORT}" >/dev/tty
    fi
    printf '  MySQL client: %s\n' "${INSTALL_MYSQL}" >/dev/tty
    printf '  Docker: %s\n' "${INSTALL_DOCKER}" >/dev/tty
    if [ "${INSTALL_DOCKER}" = true ]; then
        printf '    Docker region: %s\n' "${DOCKER_REGION}" >/dev/tty
        if [ "${DOCKER_REGION}" = cn ]; then
            printf '    Docker CE mirror: %s\n' "${DOCKER_INSTALL_MIRROR:-Aliyun}" >/dev/tty
            if [ "${DOCKER_REGISTRY_MIRROR+x}" = x ]; then
                printf '    Registry mirror: %s\n' "${DOCKER_REGISTRY_MIRROR}" >/dev/tty
            else
                printf '    Registry mirrors: mainland defaults\n' >/dev/tty
            fi
        fi
    fi
    printf '  Nginx: %s\n' "${INSTALL_NGINX}" >/dev/tty
    printf '  Rclone: %s\n' "${INSTALL_RCLONE}" >/dev/tty
    printf '  Glow: %s\n' "${INSTALL_GLOW}" >/dev/tty
    printf '  mise and Node.js LTS: %s\n' "${INSTALL_MISE}" >/dev/tty
    printf '  BBR: %s\n' "${ENABLE_BBR}" >/dev/tty
    printf '  acme.sh: %s\n\n' "${INSTALL_ACME}" >/dev/tty
}

run_interactive_wizard() {
    if ! ( : </dev/tty ) 2>/dev/null || ! ( : >/dev/tty ) 2>/dev/null; then
        err "Interactive mode requires an attached terminal."
        exit 1
    fi

    printf 'VPSReady interactive initialization\n\n' >/dev/tty
    prompt_timezone
    prompt_mirror

    printf '%s\n' \
        'SSH hardening installs or updates a public key, disables password login, and can set port 33022.' \
        >/dev/tty
    prompt_yes_no "Configure SSH hardening" "${CONFIGURE_SSH}"
    CONFIGURE_SSH="${PROMPT_VALUE}"
    if [ "${CONFIGURE_SSH}" = true ]; then
        INSTALL_SSH_KEY=true
        if [ "${NOT_INSTALL_SSH_KEY}" = true ]; then
            INSTALL_SSH_KEY=false
        fi
        prompt_yes_no "Install or update the SSH public key" "${INSTALL_SSH_KEY}"
        INSTALL_SSH_KEY="${PROMPT_VALUE}"
        if [ "${INSTALL_SSH_KEY}" = true ]; then
            prompt_ssh_key
            unset NOT_INSTALL_SSH_KEY
        else
            NOT_INSTALL_SSH_KEY=true
        fi

        CHANGE_SSH_PORT=true
        if [ "${NOT_CHANGE_SSH_PORT}" = true ]; then
            CHANGE_SSH_PORT=false
        fi
        prompt_yes_no "Change the SSH port to 33022" "${CHANGE_SSH_PORT}"
        CHANGE_SSH_PORT="${PROMPT_VALUE}"
        if [ "${CHANGE_SSH_PORT}" = true ]; then
            unset NOT_CHANGE_SSH_PORT
        else
            NOT_CHANGE_SSH_PORT=true
        fi
    fi

    prompt_email

    if [ "${TOTAL_RAM}" -le 512 ]; then
        warn "Detected ${TOTAL_RAM} MB RAM; MySQL client and Docker default to disabled."
    fi
    if [ "${TOTAL_RAM}" -le 64 ]; then
        warn "Detected ${TOTAL_RAM} MB RAM; Nginx defaults to disabled."
    fi
    if pgrep dockerd >/dev/null 2>&1; then
        warn "Docker daemon is already running; Docker defaults to disabled."
    fi

    prompt_yes_no "Install MySQL client" "${INSTALL_MYSQL}"
    INSTALL_MYSQL="${PROMPT_VALUE}"
    prompt_yes_no "Install Docker" "${INSTALL_DOCKER}"
    INSTALL_DOCKER="${PROMPT_VALUE}"
    if [ "${INSTALL_DOCKER}" = true ]; then
        prompt_docker_region
    fi
    prompt_yes_no "Install Nginx" "${INSTALL_NGINX}"
    INSTALL_NGINX="${PROMPT_VALUE}"
    prompt_yes_no "Install Rclone" "${INSTALL_RCLONE}"
    INSTALL_RCLONE="${PROMPT_VALUE}"
    prompt_yes_no "Install Glow" "${INSTALL_GLOW}"
    INSTALL_GLOW="${PROMPT_VALUE}"
    prompt_yes_no "Install mise and Node.js LTS" "${INSTALL_MISE}"
    INSTALL_MISE="${PROMPT_VALUE}"
    prompt_yes_no "Enable BBR when supported" "${ENABLE_BBR}"
    ENABLE_BBR="${PROMPT_VALUE}"
    prompt_yes_no "Install acme.sh" "${INSTALL_ACME}"
    INSTALL_ACME="${PROMPT_VALUE}"

    print_summary
    prompt_yes_no "Proceed with initialization" false
    if [ "${PROMPT_VALUE}" != true ]; then
        info "Initialization canceled."
        exit 0
    fi
}

while [ "$#" -gt 0 ]; do
    case "${1}" in
        -i)
            INTERACTIVE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown option: ${1}"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

MIRROR=$(printf '%s' "${MIRROR}" | sed 's#/$##g')
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
DOCKER_REGION="${DOCKER_REGION:-global}"
DOCKER_INSTALL_MIRROR="${DOCKER_INSTALL_MIRROR:-}"
if [ -z "${LET_MAIL}" ]; then
    LET_MAIL="webmaster@woai.ru"
fi

if ! is_valid_mirror "${MIRROR}"; then
    err "Invalid mirror URL"
    exit 1
fi

if ! is_valid_docker_region "${DOCKER_REGION}"; then
    err "DOCKER_REGION must be global or cn"
    exit 1
fi

if ! is_valid_docker_install_mirror "${DOCKER_INSTALL_MIRROR}"; then
    err "DOCKER_INSTALL_MIRROR must be Aliyun or AzureChinaCloud"
    exit 1
fi

if [ "${DOCKER_REGISTRY_MIRROR+x}" = x ] && ! is_valid_docker_registry_mirror "${DOCKER_REGISTRY_MIRROR}"; then
    err "DOCKER_REGISTRY_MIRROR must be an http:// or https:// URL, or none"
    exit 1
fi

if ! is_valid_timezone "${TIMEZONE}"; then
    err "Invalid timezone: ${TIMEZONE}"
    exit 1
fi

# 系统检测
_SUPPORT=false
if [ -n "$(command -v apt-get)" ]; then
    _SUPPORT=true
fi
if [ -n "$(command -v apk)" ]; then
    _SUPPORT=true
fi

if [ "${_SUPPORT}" = false ]; then
    err "Only support Debian/Ubuntu/Alpine"
    exit 1
fi

# 0.安装内容
INSTALL_MYSQL=true
INSTALL_DOCKER=true
INSTALL_NGINX=true
TOTAL_RAM=$(free -m | awk '$1=="This" || NR == 2' | awk '{print $2}')
if [ "${TOTAL_RAM}" -gt 8192 ]; then
    TOTAL_RAM=$(free -m | awk '$1=="This" || NR == 2' | awk '{print $7}')
fi
if [ "${TOTAL_RAM}" -le 512 ]; then
    INSTALL_MYSQL=false
    INSTALL_DOCKER=false
fi
if [ "${TOTAL_RAM}" -le 64 ]; then
    INSTALL_NGINX=false
fi
if [ "${NOT_INSTALL_DOCKER}" = true ]; then
    INSTALL_DOCKER=false
fi

# 如果已经安装了就跳过
if pgrep dockerd >/dev/null 2>&1; then
    INSTALL_DOCKER=false
fi

if [ "${INTERACTIVE}" = true ]; then
    run_interactive_wizard
    export SSHKEY NOT_INSTALL_SSH_KEY NOT_CHANGE_SSH_PORT
fi

export DOCKER_REGION DOCKER_INSTALL_MIRROR
if [ "${DOCKER_REGISTRY_MIRROR+x}" = x ]; then
    export DOCKER_REGISTRY_MIRROR
fi

chmod +x "${SCRIPT_DIR}"/scripts/install/*.sh
chmod +x "${SCRIPT_DIR}"/scripts/configure/*.sh
chmod +x "${SCRIPT_DIR}"/scripts/tools/*.sh

install_packages_separately() {
    PACKAGE_MANAGER="${1}"
    shift
    FAILED_PACKAGES=""

    for PACKAGE in "$@"; do
        if [ "${PACKAGE_MANAGER}" = "apt" ]; then
            if apt-get -y install "${PACKAGE}" >/dev/null 2>&1; then
                :
            else
                warn "Failed to install package: ${PACKAGE}"
                FAILED_PACKAGES="${FAILED_PACKAGES}${FAILED_PACKAGES:+ }${PACKAGE}"
            fi
        elif [ "${PACKAGE_MANAGER}" = "apk" ]; then
            if apk add --update --no-cache "${PACKAGE}" >/dev/null 2>&1; then
                :
            else
                warn "Failed to install package: ${PACKAGE}"
                FAILED_PACKAGES="${FAILED_PACKAGES}${FAILED_PACKAGES:+ }${PACKAGE}"
            fi
        fi
    done

    if [ -n "${FAILED_PACKAGES}" ]; then
        warn "Skipped failed packages: ${FAILED_PACKAGES}"
    fi
}

# 检查MIRROR是否为空
if [ -n "${MIRROR}" ]; then
    # 使用sed在末尾添加斜杠
    MIRROR="${MIRROR}/"
    export GH_MIRROR="${MIRROR}"
    if [ -f /data/.profile ]; then
        sed -i "s@^export GH_MIRROR=.*@export GH_MIRROR=${MIRROR}@" /data/.profile
    else
        echo "export GH_MIRROR=${MIRROR}" >>/data/.profile
    fi
fi
# 1.安装基础软件包
info "Install required software"
if [ -n "$(command -v apt-get)" ]; then
    apt-get update >/dev/null
    install_packages_separately apt curl ca-certificates vim unzip ftp openssl bash cron lrzsz iproute2
    [ "$INSTALL_MYSQL" = true ] && install_packages_separately apt default-mysql-client
elif [ -n "$(command -v apk)" ]; then
    install_packages_separately apk curl ca-certificates vim unzip lftp tzdata openssl bash dcron iproute2-ss
    [ "$INSTALL_MYSQL" = true ] && install_packages_separately apk mysql-client
else
    err "Do not support your system!"
    exit 1
fi

# Alpine 特殊处理：切换默认 shell 为 bash
if [ -n "$(command -v apk)" ]; then
    info "Setting bash as default shell for Alpine"
    if [ -f /bin/bash ]; then
        # 使用 chsh 切换当前用户的 shell
        if command -v chsh >/dev/null 2>&1; then
            chsh -s /bin/bash >/dev/null 2>&1
        fi
        # 确保 bash 在 /etc/shells 中
        if ! grep -q "/bin/bash" /etc/shells 2>/dev/null; then
            echo "/bin/bash" >> /etc/shells
        fi
        suc "Default shell changed to bash"
    else
        warn "Bash not found, skipping shell change"
    fi
fi

# tzdata is installed above on Alpine before timezone activation.
if [ ! -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    err "Timezone data not found: ${TIMEZONE}"
    exit 1
fi

# 2.设置时区
info "Modify timezone"
if [ -n "$(command -v timedatectl)" ]; then
    timedatectl set-timezone "${TIMEZONE}"
else
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
fi
if uname -a | grep -q "Microsoft"; then
    info "WSL Environment. Skip OpenSSH / Docker Configure!"
else
    if [ "${CONFIGURE_SSH}" = true ]; then
        if [ -f "/usr/sbin/scw-fetch-ssh-keys" ]; then
            # 兼容 Scaleway
            # 添加计划任务
            if [ -n "$(command -v crontab)" ]; then
                if ! crontab -l | grep -q "/data/scripts/configure/ssh_key.sh"; then
                    (
                        crontab -l 2>/dev/null
                        echo "@reboot sh /data/scripts/configure/ssh_key.sh -k"
                    ) | crontab -
                fi
            fi
            if [ "${NOT_CHANGE_SSH_PORT}" != "true" ]; then
                if [ -f /data/.profile ]; then
                    sed -i '/^NOT_CHANGE_SSH_PORT/d' /data/.profile
                fi
                echo "export NOT_CHANGE_SSH_PORT=true" >>/data/.profile
                if [ -n "$(command -v crontab)" ]; then
                    if ! crontab -l | grep -q "/data/scripts/configure/ssh_port.sh"; then
                        (
                            crontab -l 2>/dev/null
                            echo "@reboot /data/scripts/configure/ssh_port.sh"
                        ) | crontab -
                    fi
                fi
            fi
        fi

        # 处理 SSHKEY 环境变量，仅用于当前初始化，避免覆盖现有公钥文件
        if [ -n "${SSHKEY}" ]; then
            info "Using SSH public key from environment for this run"
        fi

        /data/scripts/configure/ssh_port.sh
    else
        info "Skip SSH hardening"
    fi
    # 4.新增用户
    [ "${INSTALL_MYSQL}" = true ] && /usr/sbin/useradd -u 1001 -s /sbin/nologin mysql 2>/dev/null
    /usr/sbin/useradd -u 1002 -s /sbin/nologin www 2>/dev/null
    # 5.安装 Docker
    if [ "${INSTALL_DOCKER}" = true ] && [ -z "$(command -v docker)" ]; then
        info "Installing Docker"
        if [ -f /data/scripts/install/docker.sh ]; then
            chmod +x /data/scripts/install/docker.sh
            /data/scripts/install/docker.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/docker.sh" -o -)"
        fi
        # 启动 Docker 服务
        if [ -n "$(command -v systemctl)" ]; then
            systemctl enable docker
            systemctl start docker
        elif [ -n "$(command -v rc-service)" ]; then
            # Alpine Linux (OpenRC)
            rc-update add docker boot
            rc-service docker start
        elif [ -n "$(command -v service)" ]; then
            service docker start
        fi
    else
        info "Skip install Docker"
    fi
    # 创建默认 Docker Compose 配置
    if [ "${INSTALL_DOCKER}" = true ] && [ ! -f /data/docker-compose.yml ] && [ -f /data/.docker-compose.yml.demo ]; then
        if cp -f /data/.docker-compose.yml.demo /data/docker-compose.yml >/dev/null; then
            info "Create /data/docker-compose.yml"
        else
            err "Cannot create /data/docker-compose.yml"
        fi
    fi
    # Nginx
    [ "${INSTALL_NGINX}" = true ] && {
        if [ -f /data/scripts/install/nginx.sh ]; then
            /data/scripts/install/nginx.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/nginx.sh" -o -)"
        fi
    }
fi

# 6.配置 vim
if [ ! -f /root/.vimrc ]; then
    info "Configure vim"
        ln -sf /data/config/.vimrc /root/.vimrc
fi

# 7.安装 ez-bash
if [ ! -d /data/.ez ]; then
    git clone "${MIRROR}https://github.com/benzBrake/.ez-bash" /data/.ez
    chmod +x /data/.ez/*.bash
    chmod +x /data/.ez/*/*.bash
fi

# 8.环境变量
if grep "/data/.ezenv" /root/.bashrc >/dev/null; then
    info "Utils env is set."
else
    info "Setting utils env."
    echo '. "/data/.ezenv"' >>/root/.bashrc
fi

# 9.安装 Rclone
if [ "${INSTALL_RCLONE}" = true ]; then
    if [ -z "$(command -v rclone)" ]; then
        mkdir /data/rclone
        curl https://rclone.org/install.sh | bash
    else
        info "Rclone already installed, skip"
    fi
else
    info "Skip install Rclone"
fi

# 10.安装 Glow
if [ "${INSTALL_GLOW}" = true ]; then
    if [ -z "$(command -v glow)" ]; then
        info "Installing Glow"
        if [ -f /data/scripts/install/glow.sh ]; then
            . /data/scripts/install/glow.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/glow.sh" -o -)"
        fi
    else
        info "Glow already installed, skip"
    fi
else
    info "Skip install Glow"
fi

# 11.安装 mise 和最新 LTS Node.js
if [ "${INSTALL_MISE}" = true ]; then
    if [ -f "${SCRIPT_DIR}/scripts/install/mise.sh" ]; then
        "${SCRIPT_DIR}/scripts/install/mise.sh"
    else
        bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/mise.sh" -o -)"
    fi
else
    info "Skip install mise and Node.js LTS"
fi

# 12.启用 BBR
if [ "${ENABLE_BBR}" = true ]; then
    if sysctl net.ipv4.tcp_available_congestion_control | grep bbr; then
        echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
        sysctl -p
    fi
else
    info "Skip enable BBR"
fi

# 13.安装 acme.sh
if [ "${INSTALL_ACME}" = true ]; then
    if [ ! -d /data/.acme.sh ]; then
        curl https://get.acme.sh | sh
        MIRROR="${MIRROR}" LET_MAIL="${LET_MAIL}" sh /data/scripts/install/acme.sh
    fi
else
    info "Skip install acme.sh"
fi

suc "ALL Done"
