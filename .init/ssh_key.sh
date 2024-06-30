#!/usr/bin/env sh
source /data/.profile
if [ -z "${KEY_URL}" ]; then
    KEY_URL="${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/pub/xiaoji.pub"
fi

# Function to generate a random number
randomNum() {
    command -v shuf >/dev/null && shuf -i 100000-999999 -n 1 || jot -r 1 100000 999999
}

# 安装公钥
echo "Install public key"
mkdir -p /tmp "$HOME/.ssh" >/dev/null
PUBKeyFile="/tmp/$(randomNum).pub"
while :; do
    echo >/dev/null
    [ ! -f "${PUBKeyFile}" ] && break
    PUBKeyFile="/tmp/$(randomNum).pub"
done

# 有本地用本地（Git clone 项目的时候本地有 key），没有就从 Mirror 下载
if [ -f /data/pub/xiaoji.pub ]; then
    echo "Local public key not found, downloading..."
    cp /data/pub/xiaoji.pub "${PUBKeyFile}" >/dev/null
else
    curl -sSL "${KEY_URL}" -o "${PUBKeyFile}"
fi

if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    cat "${PUBKeyFile}" >>"$HOME/.ssh/authorized_keys"
else
    AuthKeyStr=$(cat "$HOME/.ssh/authorized_keys")
    PUBKeyStr=$(awk '{$1=$1};1' <"${PUBKeyFile}")
    CompareResult=$(echo "${AuthKeyStr}" | grep "${PUBKeyStr}")
    [ "$CompareResult" = "" ] && {
        cat "${PUBKeyFile}" >>"$HOME/.ssh/authorized_keys"
    }
    chmod 600 "$HOME/.ssh/authorized_keys" >/dev/null
fi

# 清理临时文件
[ -n "${PUBKeyFile}" ] && rm -rf "${PUBKeyFile}"
