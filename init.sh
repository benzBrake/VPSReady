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

MIRROR=$(echo "${MIRROR-https://raw.githubusercontent.com/benzBrake/VPSReady/main}" | sed 's#/$##g')

# 系统检测
_SUPPORT=fasle
if [ ! -z "$(command -v apt-get)" ]; then
    _SUPPORT=true
fi
if [ ! -z "$(command -v apk)" ]; then
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
if [ "$TOTAL_RAM" -le 512 ]; then
    INSTALL_MYSQL=false
    INSTALL_DOCKER=false
fi
if [ "$TOTAL_RAM" -le 64 ]; then
    INSTALL_NGINX=false
fi

# 1.安装基础软件包
info "Install required software"
if [ -n "$(command -v apt-get)" ]; then
    apt-get update >/dev/null
    apt-get -y install curl ca-certificates vim unzip ftp >/dev/null
    [ "$INSTALL_MYSQL" = true ] && apt-get -y install default-mysql-client >/dev/null
elif [ -n "$(command -v apk)" ]; then
    apk add --update --no-cache curl ca-certificates vim ftp tzdata >/dev/null
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
        # 添加公钥 xiaoji
        info "Install public key"
        mkdir -p /tmp ~/.ssh >/dev/null
        PUBKeyFile="/tmp/$(randomNum).pub"
        while :; do
            echo >/dev/null
            [ ! -f "${PUBKeyFile}" ] && break
            PUBKeyFile="/tmp/$(randomNum).pub"
        done
        # 有本地用本地（Git clone 项目的时候本地有key），没有就从 Mirror 下载
        if [ -f /data/pub/xiaoji.pub ]; then
            info "Local public key not found, downloading..."
            cp /data/pub/xiaoji.pub "${PUBKeyFile}" >/dev/null
        else
            curl -sSL "${MIRROR}/pub/xiaoji.pub" -o "${PUBKeyFile}"
        fi
        if [ ! -f ~/.ssh/authorized_keys ]; then
            cat "${PUBKeyFile}" >>~/.ssh/authorized_keys
        else
            AuthKeyStr=$(cat ~/.ssh/authorized_keys)
            PUBKeyStr=$(sed <"${PUBKeyFile}" 's@^\s*@@;s@\s*$@@')
            CompareResult=$(echo "${AuthKeyStr}" | grep "${PUBKeyStr}")
            [ "$CompareResult" = "" ] && {
                cat "${PUBKeyFile}" >>~/.ssh/authorized_keys
            }
            chmod 600 ~/.ssh/authorized_keys >/dev/null
        fi
        # 仅公钥登录
        info "Enable only login with public key"
        if grep -i '^PasswordAuthentication\s\+no' /etc/ssh/sshd_config >/dev/null; then
            if grep -i '^PasswordAuthentication\s\+yes' /etc/ssh/sshd_config >/dev/null; then
                sed -i "s@^PasswordAuthentication\s\+yes@PasswordAuthentication no@" /etc/ssh/sshd_config
            else
                if grep -i '^#PasswordAuthentication.*' /etc/ssh/sshd_config >/dev/null; then
                    sed -i "s@^#PasswordAuthentication.*@&\nPasswordAuthentication no@" /etc/ssh/sshd_config
                else
                    echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
                fi
            fi
        fi
        # SSH端口
        info "Change SSH port to 33022"
        RESULT=$(grep "^[pP][oO][rR][tT]\s*" /etc/ssh/sshd_config)
        if [ -n "$RESULT" ]; then
            sed -i "s#$RESULT#Port 33022#" /etc/ssh/sshd_config
        else
            sed -i "5aPort 33022" /etc/ssh/sshd_config
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
            bash -c "$(curl -sSL "${MIRROR}/.init/docker.sh" -o -)"
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
            bash -c "$(curl -sSL "${MIRROR}/.init/nginx.sh" -o -)"
        fi
    }
fi

# 6.配置 vim
if [ ! -f /root/.vimrc ]; then
    info "Configure vim"
    ln -sf /data/.init/.vimrc /root/.vimrc
fi

# 7.安装 ez-bash
git clone https://github.com/benzBrake/.ez-bash /data/.ez
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
sysctl net.ipv4.tcp_available_congestion_control | grep bbr
if [ $? -ne 0 ]; then
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.con
    sysctl -p
fi

suc "ALL Done"
