#!/bin/sh
###
 # @Author: Ryan
 # @Date: 2021-02-22 20:18:53
 # @LastEditTime: 2021-02-23 14:54:24
 # @LastEditors: Ryan
 # @Description: VPS初始化脚本
 # @FilePath: \VPSReady\init.sh
###
randomNum() {
    awk -v min=10000 -v max=99999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}
if [ -z "$(command -v apt-get)" ]; then
    exit 1
fi
MIRROR=$(echo "${MIRROR-https://raw.githubusercontent.com/benzBrake/VPSReady/main}" | sed 's#/$##g')
# 0.询问安装内容
# 1.安装基础软件包
apt-get update
apt-get -y install curl ca-certificates vim
# 2.设置时区
if [ -n "$(command -v timedatectl)" ]; then
    timedatectl set-timezone Asia/Shanghai
else
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi
# 3.设置SSH登录参数
if [ -e "/etc/ssh/sshd_config" ]; then
    #备份SSH配置
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    #添加公钥 xiaoji
    mkdir -p /tmp ~/.ssh
    PUBKeyFile="/tmp/$(randomNum).pub"
    while :; do echo
        [ ! -f "${PUBKeyFile}" ] && break
        PUBKeyFile="/tmp/$(randomNum).pub"
    done
    # 有本地用本地（Git clone 项目的时候本地有key），没有就从 Mirror 下载
    if [ -f ./pub/xiaoji.pub ]; then
        cp ./pub/xiaoji.pub ${PUBKeyFile}
    else
        curl -sSL "${MIRROR}/pub/xiaoji.pub" -o "${PUBKeyFile}"
    fi
    if [ ! -f ~/.ssh/authorized_keys ]; then
        cat ${PUBKeyFile} >> ~/.ssh/authorized_keys
    else
        AuthKeyStr=$(cat ~/.ssh/authorized_keys)
        PUBKeyStr=$(< ${PUBKeyFile} sed 's@^\s*@@;s@\s*$@@')
        CompareResult=$(echo "${AuthKeyStr}" | grep "${PUBKeyStr}")
        [ "$CompareResult" = "" ] && {
            cat ${PUBKeyFile} >> ~/.ssh/authorized_keys
        }
        chmod 600 ~/.ssh/authorized_keys
    fi
    # 仅公钥登录
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
    if grep "^[pP][oO][rR][tT]\s\+$aa" /etc/ssh/sshd_config >/dev/null; then
        if grep '#[pP][oO][rR][tT].*' /etc/ssh/sshd_config >/dev/null; then
            sed -i "5aPort 33022" /etc/ssh/sshd_config
        else
            sed -i "s@^#port.*@&\nPort 33022@i" /etc/ssh/sshd_config
        fi
    else
        sed -i 's@^port.*@Port 33022@i' /etc/ssh/sshd_config
    fi
    #重启SSH服务
    if [ -n "$(command -v systemctl)" ]; then
        systemctl restart sshd
    else
        service sshd restart
        service ssh restart
    fi
    #清理垃圾
    rm -rf ${PUBKeyFile}
else
    echo "Do not support none OpenSSH Server!"
fi
4.安装 Docker
if [ -f ./docker.sh ]; then
    chmod +x ./docker.sh
    ./docker.sh
else
    bash -c "$(curl -sSL "${MIRROR}/docker.sh" -o -)"
fi
echo "ALL Done"
