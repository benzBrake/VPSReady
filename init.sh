#!/usr/bin/env sh

randomNum() {
    awk -v min=10000 -v max=99999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}
info() {
    echo "[I] $*"
}
warn() {
    echo "[W] $*"
}
err() {
    echo "[E] $*"
}
suc() {
    echo "[S] $*"
}

MIRROR=$(echo "${MIRROR}" | sed 's#/$##g')
# 检查MIRROR是否为空
if [ -n "${MIRROR}" ]; then
    # 使用sed在末尾添加斜杠
    MIRROR="${MIRROR}/"
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
# 如果已经安装了就跳过

if pgrep dockerd >/dev/null 2>&1; then
    INSTALL_DOCKER=false
fi
# 1.安装基础软件包
info "Install required software"
if [ -n "$(command -v apt-get)" ]; then
    apt-get update >/dev/null
    apt-get -y install curl ca-certificates vim unzip ftp openssl bash >/dev/null
    [ "$INSTALL_MYSQL" = true ] && apt-get -y install default-mysql-client >/dev/null
elif [ -n "$(command -v apk)" ]; then
    apk add --update --no-cache curl ca-certificates vim lftp tzdata openssl bash >/dev/null
    [ "$INSTALL_MYSQL" = true ] && apk add --update --nocache mysql-client >/dev/null
else
    err "Do not support your system!"
    exit 1
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
    # 3.设置SSH登录参数
    if [ -e "/etc/ssh/sshd_config" ]; then
        # 备份SSH配置
        info "Backup SSH config"
        cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        if [ -f "/data/.init/ssh_key.sh" ]; then
            sh /data/.init/ssh_key.sh MIRROR="${MIRROR}"
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/ssh_key.sh" -o -)"
        fi
        # 仅公钥登录
        info "Enable only login with public key"
        if grep -i '^PasswordAuthentication.*' /etc/ssh/sshd_config >/dev/null; then
            sed -i "s@^PasswordAuthentication.*@PasswordAuthentication no@" /etc/ssh/sshd_config
        else
            if grep -i '^#PasswordAuthentication.*' /etc/ssh/sshd_config >/dev/null; then
                sed -i "s@^#PasswordAuthentication.*@&\nPasswordAuthentication no@" /etc/ssh/sshd_config
            else
                echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
            fi
        fi
        # SSH端口
        if [ "$NOT_CHANGE_SSH_PORT" != "true" ]; then
            info "Change SSH port to 33022"
            RESULT=$(grep "^[pP][oO][rR][tT]\s*" /etc/ssh/sshd_config)
            if [ -n "$RESULT" ]; then
                sed -i "s#$RESULT#Port 33022#" /etc/ssh/sshd_config
            else
                RESULT=$(grep "^#[pP][oO][rR][tT]\s*" /etc/ssh/sshd_config)
                if [ -n "$RESULT" ]; then
                    sed -i "/^#[pP][oO][rR][tT]\s*/a Port 33022" /etc/ssh/sshd_config
                else
                    echo "Port 33022" >> /etc/ssh/sshd_config
                fi
                
            fi
        fi
        # 重启SSH服务
        info "Restart SSH Service"
        if [ -n "$(command -v systemctl)" ]; then
            if systemctl restart sshd; then
                info "Remove SSH Config Backup"
                rm -f /etc/ssh/sshd_config.bak >/dev/null
            else
                err "Modify SSH config Failed."
                info "Restoring SSH Config..."
                rm -f /etc/ssh/sshd_config >/dev/null
                mv -f /etc/ssh/sshd_config.bak /etc/ssh/sshd_config >/dev/null
            fi
        else
            service sshd restart
            service ssh restart
        fi
        # 清理临时文件
        [ -n "${PUBKeyFile}" ] && rm -rf "${PUBKeyFile}"
    else
        warn "Do not support none OpenSSH Server!"
    fi
    # 4.新增用户
    [ $INSTALL_MYSQL = true ] && /usr/sbin/useradd -u 1001 mysql 2>/dev/null
    /usr/sbin/useradd -u 1002 www 2>/dev/null
    # 5.安装 Docker
    if [ $INSTALL_DOCKER = true ] && [ -z "$(command -v docker)" ]; then
        info "Installing Docker"
        if [ -f /data/.init/docker.sh ]; then
            chmod +x /data/.init/docker.sh
            /data/.init/docker.sh
        else
            bash -c "$(curl -sSL "${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/docker.sh" -o -)"
        fi
        systemctl enable docker
        systemctl start docker
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
            chmod +x /data/.init/nginx.sh
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
git clone "${MIRROR}https://github.com/benzBrake/.ez-bash" /data/.ez
chmod +x /data/.ez/*.bash
chmod +x /data/.ez/*/*.bash

# 8.Utils 配置
if grep "/data/.ezenv" /root/.bashrc >/dev/null; then
    info "Utils env is set."
else
    info "Setting utils env."
    echo '. "/data/.ezenv"' >>/root/.bashrc
fi
chmod +x /data/.utils/* >/dev/null

# 9.安装 Rclone
mkdir /data/rclone
curl https://rclone.org/install.sh | bash

# 10.启用 BBR
if sysctl net.ipv4.tcp_available_congestion_control | grep bbr; then
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.con
    sysctl -p
fi

# 11.安装 acme.sh
sh /data/.init/acme.sh MIRROR="${MIRROR}" LET_MAIL="${LET_MAIL}"

suc "ALL Done"
