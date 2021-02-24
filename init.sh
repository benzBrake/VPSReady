#!/bin/sh
###
 # @Author: Ryan
 # @Date: 2021-02-22 20:18:53
 # @LastEditTime: 2021-02-24 09:12:18
 # @LastEditors: Ryan
 # @Description: VPS初始化脚本 For Debian/Ubuntu
 # @FilePath: \VPSReady\init.sh
###
randomNum() {
    awk -v min=10000 -v max=99999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}
info () {
    echo "[I] $*"
}
warn () {
    echo "[W] $*"
}
err () {
    echo "[E] $*"
}
suc () {
    echo "[S] $*"
}
if [ -z "$(command -v apt-get)" ]; then
    err "Only support Debian/Ubuntu"
    exit 1
fi
MIRROR=$(echo "${MIRROR-https://raw.githubusercontent.com/benzBrake/VPSReady/main}" | sed 's#/$##g')
# 0.询问安装内容
# 1.安装基础软件包
info "Installing required software"
apt-get update
apt-get -y install curl ca-certificates vim
# 2.设置时区
info "Modifying timezone"
if [ -n "$(command -v timedatectl)" ]; then
    timedatectl set-timezone Asia/Shanghai
else
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi
# 3.设置SSH登录参数
if [ -e "/etc/ssh/sshd_config" ]; then
    # 备份SSH配置
    info "Backuping SSH config"
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    # 添加公钥 xiaoji
    info "Installing public key"
    mkdir -p /tmp ~/.ssh > /dev/null
    PUBKeyFile="/tmp/$(randomNum).pub"
    while :; do echo
        [ ! -f "${PUBKeyFile}" ] && break
        PUBKeyFile="/tmp/$(randomNum).pub"
    done
    # 有本地用本地（Git clone 项目的时候本地有key），没有就从 Mirror 下载
    if [ -f /data/pub/xiaoji.pub ]; then
        info "Local public key not found, downloading..."
        cp /data/pub/xiaoji.pub "${PUBKeyFile}" >  /dev/null
    else
        curl -sSL "${MIRROR}/pub/xiaoji.pub" -o "${PUBKeyFile}"
    fi
    if [ ! -f ~/.ssh/authorized_keys ]; then
        cat "${PUBKeyFile}" >> ~/.ssh/authorized_keys
    else
        AuthKeyStr=$(cat ~/.ssh/authorized_keys)
        PUBKeyStr=$(< "${PUBKeyFile}" sed 's@^\s*@@;s@\s*$@@')
        CompareResult=$(echo "${AuthKeyStr}" | grep "${PUBKeyStr}")
        [ "$CompareResult" = "" ] && {
            cat "${PUBKeyFile}" >> ~/.ssh/authorized_keys
        }
        chmod 600 ~/.ssh/authorized_keys > /dev/null
    fi
    # 仅公钥登录
    info "Enabling only login with public key"
    if grep -i '^PasswordAuthentication\s\+no' /etc/ssh/sshd_config >/dev/null; then
        if grep -i  '^PasswordAuthentication\s\+yes'  /etc/ssh/sshd_config >/dev/null; then
            sed -i "s@^PasswordAuthentication\s\+yes@PasswordAuthentication no@" /etc/ssh/sshd_config
        else
            if grep -i  '^#PasswordAuthentication.*'  /etc/ssh/sshd_config >/dev/null; then
                sed -i "s@^#PasswordAuthentication.*@&\nPasswordAuthentication no@" /etc/ssh/sshd_config
            else
                echo 'PasswordAuthentication no'>> /etc/ssh/sshd_config
            fi
        fi
    fi
    # SSH端口
    info "Changing SSH port to 33022"
    if grep "^[pP][oO][rR][tT]\s\+$aa" /etc/ssh/sshd_config >/dev/null; then
        if grep '#[pP][oO][rR][tT].*' /etc/ssh/sshd_config >/dev/null; then
            sed -i "5aPort 33022" /etc/ssh/sshd_config
        else
            sed -i "s@^#port.*@&\nPort 33022@i" /etc/ssh/sshd_config
        fi
    else
        sed -i 's@^port.*@Port 33022@i' /etc/ssh/sshd_config
    fi
    # 重启SSH服务
    if [ -n "$(command -v systemctl)" ]; then
        if systemctl restart sshd; then
            info "Removing SSH Config Backup..."
            rm -f /etc/ssh/sshd_config.bak > /dev/null
        else
            err "Modify SSH config Failed."
            info "Restoring SSH Config..."
            rm -f /etc/ssh/sshd_config > /dev/null
            mv -f /etc/ssh/sshd_config.bak /etc/ssh/sshd_config > /dev/null
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
/usr/sbin/useradd -u 1001 mysql
/usr/sbin/useradd -u 1002 www
# 5.安装 Docker
if [ -z "$(command -v docker)" ]; then
    info "Installing Docker"
    if [ -f /data/.init/docker.sh ]; then
        chmod +x /data/.init/docker.sh
        /data/.init/docker.sh
    else
        bash -c "$(curl -sSL "${MIRROR}/.init/docker.sh" -o -)"
    fi
else
    info "Skip install Docker"
fi
# 创建默认 Docker Compose 配置
if [ ! -f /data/docker-compose.yml ] && [ -f /data/.docker-compose.yml.demo ]; then
    if cp -f /data/.docker-compose.yml.demo /data/docker-compose.yml > /dev/null; then
        info "Create /data/docker-compose.yml"
    else
        err "Cannot create /data/docker-compose.yml"
    fi
fi
suc "ALL Done"