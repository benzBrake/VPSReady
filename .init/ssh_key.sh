#!/usr/bin/env sh
if [ -z "${KEY_URL}" ]; then
    KEY_URL="${MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/pub/xiaoji.pub"
fi
# 安装公钥
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
    curl -sSL "${KEY_URL}" -o "${PUBKeyFile}"
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
