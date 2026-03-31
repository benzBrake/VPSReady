#!/usr/bin/env sh

SCRIPT_DIR=$(
    cd "$(dirname "")"
    pwd
)
chmod +x "${SCRIPT_DIR}"/.init/*.sh
chmod +x "${SCRIPT_DIR}"/.utils/*

. "${SCRIPT_DIR}"/.utils/common.sh

install_packages_separately() {
    package_manager="$1"
    shift
    failed_packages=""

    for package in "$@"; do
        if [ "$package_manager" = "apt" ]; then
            if apt-get -y install "$package" >/dev/null 2>&1; then
                :
            else
                warn "Failed to install package: ${package}"
                failed_packages="${failed_packages}${failed_packages:+ }${package}"
            fi
        elif [ "$package_manager" = "apk" ]; then
            if apk add --update --no-cache "$package" >/dev/null 2>&1; then
                :
            else
                warn "Failed to install package: ${package}"
                failed_packages="${failed_packages}${failed_packages:+ }${package}"
            fi
        fi
    done

    if [ -n "$failed_packages" ]; then
        warn "Skipped failed packages: ${failed_packages}"
    fi
}

MIRROR=$(echo "${MIRROR}" | sed 's#/$##g')
# 检查MIRROR是否为空
if [ -n "${MIRROR}" ]; then
    # 使用sed在末尾添加斜杠
    MIRROR="${MIRROR}/"
    if [ -f /data/.profile ]; then
        sed -i "s@^export GH_MIRROR=.*@export GH_MIRROR=${MIRROR}@" /data/.profile
    else
        echo "export GH_MIRROR=${MIRROR}" >>/data/.profile
    fi
fi

if [ -z "${LET_MAIL}" ]; then
    LET_MAIL="webmaster@woai.ru"
fi

# 系统检测
_SUPPORT=false
if [ -n "$(command -v apt-get)" ]; then
    _SUPPORT=true
fi
if [ -n "$(command -v apk)" ]; then
    _SUPPORT=true
fi

if [ "$_SUPPORT" = false ]; then
    err "Only support Debian/Ubuntu/Alpine"
    exit 1
fi

# 0.安装内容
INSTALL_MYSQL=true
INSTALL_DOCKER=true
INSTALL_NGINX=true
TOTAL_RAM=$(free -m | awk '$1=="This" || NR == 2' | awk '{print $2}')
if [ "$TOTAL_RAM" -gt 8192 ]; then
    TOTAL_RAM=$(free -m | awk '$1=="This" || NR == 2' | awk '{print $7}')
fi
if [ "$TOTAL_RAM" -le 512 ]; then
    INSTALL_MYSQL=false
    INSTALL_DOCKER=false
fi
if [ "$TOTAL_RAM" -le 64 ]; then
    INSTALL_NGINX=false
fi
if [ "$NOT_INSTALL_DOCKER" = true ]; then
    INSTALL_DOCKER=false
fi
# 如果已经安装了就跳过

if pgrep dockerd >/dev/null 2>&1; then
    INSTALL_DOCKER=false
fi
# 1.安装基础软件包
info "Install required software"
if [ -n "$(command -v apt-get)" ]; then
    apt-get update >/dev/null
    install_packages_separately apt curl ca-certificates vim unzip ftp openssl bash crontab lrzsz iproute2
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

# 2.设置时区
info "Modify timezone"
if [ -n "$(command -v timedatectl)" ]; then
    timedatectl set-timezone Asia/Shanghai
else
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi
if uname -a | grep -q "Microsoft"; then
    info "WSL Environment. Skip OpenSSH / Docker Configure!"
else
    if [ -f "/usr/sbin/scw-fetch-ssh-keys" ]; then
        # 兼容 Scaleway
        # 添加计划任务
        if [ -n "$(command -v crontab)" ]; then
            if ! crontab -l | grep -q "/data/.init/ssh_key.sh"; then
                (
                    crontab -l 2>/dev/null
                    echo "@reboot /data/.init/ssh_key.sh"
                ) | crontab -
            fi
        fi
        if [ "$NOT_CHANGE_SSH_PORT" != "true" ]; then
            if [ -f /data/.profile ]; then
                sed -i '/^NOT_CHANGE_SSH_PORT/d' /data/.profile
            fi
            echo "export NOT_CHANGE_SSH_PORT=true" >>/data/.profile
            if [ -n "$(command -v crontab)" ]; then
                if ! crontab -l | grep -q "/data/.init/ssh_port.sh"; then
                    (
                        crontab -l 2>/dev/null
                        echo "@reboot /data/.init/ssh_port.sh"
                    ) | crontab -
                fi
            fi
        fi
    fi

    # 处理 SSHKEY 环境变量，仅用于当前初始化，避免覆盖现有公钥文件
    if [ -n "${SSHKEY}" ]; then
        info "Using SSH public key from environment for this run"
    fi

    /data/.init/ssh_key.sh
    /data/.init/ssh_port.sh
    # 4.新增用户
    [ $INSTALL_MYSQL = true ] && /usr/sbin/useradd -u 1001 -s /sbin/nologin mysql 2>/dev/null
    /usr/sbin/useradd -u 1002 -s /sbin/nologin www 2>/dev/null
    # 5.安装 Docker
    if [ $INSTALL_DOCKER = true ] && [ -z "$(command -v docker)" ]; then
        info "Installing Docker"
        if [ -f /data/.init/docker.sh ]; then
            chmod +x /data/.init/docker.sh
            /data/.init/docker.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/docker.sh" -o -)"
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
    if [ $INSTALL_DOCKER = true ] && [ ! -f /data/docker-compose.yml ] && [ -f /data/.docker-compose.yml.demo ]; then
        if cp -f /data/.docker-compose.yml.demo /data/docker-compose.yml >/dev/null; then
            info "Create /data/docker-compose.yml"
        else
            err "Cannot create /data/docker-compose.yml"
        fi
    fi
    # Nginx
    [ $INSTALL_NGINX = true ] && {
        if [ -f /data/.init/nginx.sh ]; then
            /data/.init/nginx.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/nginx.sh" -o -)"
        fi
    }
fi

# 6.配置 vim
if [ ! -f /root/.vimrc ]; then
    info "Configure vim"
    ln -sf /data/.init/.vimrc /root/.vimrc
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
if [ -z "$(command -v rclone)" ]; then
    mkdir /data/rclone
    curl https://rclone.org/install.sh | bash
else
    info "Rclone already installed, skip"
fi

# 10.启用 BBR
if sysctl net.ipv4.tcp_available_congestion_control | grep bbr; then
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.con
    sysctl -p
fi

# 11.安装 acme.sh
if [ ! -d /data/.acme.sh ]; then
    curl https://get.acme.sh | sh
    sh /data/.init/acme.sh MIRROR="${MIRROR}" LET_MAIL="${LET_MAIL}"
fi

suc "ALL Done"
