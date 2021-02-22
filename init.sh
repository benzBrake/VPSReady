#!/bin/sh
###
 # @Author: Ryan
 # @Date: 2021-02-22 20:18:53
 # @LastEditTime: 2021-02-22 20:44:53
 # @LastEditors: Ryan
 # @Description: 
 # @FilePath: \VPSReady\init.sh
###
if [ -z "$(command -v apt-get)" ]; then
    exit 1
fi
MIRROR=$(echo ${MIRROR-https://raw.githubusercontent.com/benzBrake/VPSReady/main} | sed 's#/$##g')
# 0.询问安装内容
# 1.安装基础软件包
apt-get update
apt-get -y install curl ca-certificates vim
# 2.设置时区
if [ ! -z "$(command -v timedatectl)" ]; then
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
    PKF="/tmp/$RANDOM.pub"
    while :; do echo
        [[ ! -f "$PKF" ]] && break
        PKF="/tmp/$RANDOM.pub"
    done
    curl -o $PKF ${MIRROR}/pub/xiaoji.pub
    if [ ! -f ~/.ssh/authorized_keys ]; then
        cat $PKF >> ~/.ssh/authorized_keys
    else
        AUTHSTR=$(cat ~/.ssh/authorized_keys)
        PKFSTR=$(cat $PKF | sed 's@^\s*@@;s@\s*$@@')
        COMPARE=$(echo $AUTHSTR | grep "$PKFSTR")
        [[ "$COMPARE" == "" ]] && {
            cat $PKF >> ~/.ssh/authorized_keys
        }
        chmod 600 ~/.ssh/authorized_keys
    fi
    # 仅公钥登录
    grep -i '^PasswordAuthentication\s\+no' /etc/ssh/sshd_config >/dev/null
    [[ $? -ne 0 ]] && {
        grep -i  '^PasswordAuthentication\s\+yes'  /etc/ssh/sshd_config >/dev/null
        if [[ $? -eq 0 ]]; then
            sed -i "s@^PasswordAuthentication\s\+yes@PasswordAuthentication no@" /etc/ssh/sshd_config
        else
            grep -i  '^#PasswordAuthentication.*'  /etc/ssh/sshd_config >/dev/null
            if [[ $? -eq 0 ]]; then
                sed -i "s@^#PasswordAuthentication.*@&\nPasswordAuthentication no@" /etc/ssh/sshd_config
            else
                echo 'PasswordAuthentication no'>> /etc/ssh/sshd_config
            fi
        fi
    }
    # SSH端口
    grep "^[pP][oO][rR][tT]\s\+$aa" /etc/ssh/sshd_config >/dev/null
    if test $? -ne 0 ; then
        grep '#[pP][oO][rR][tT].*' /etc/ssh/sshd_config >/dev/null
        if [ $? -ne 0 ]; then
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
    rm -rf $PKF
else
    echo "Do not support none OpenSSH Server!"
fi
echo "ALL Done"
