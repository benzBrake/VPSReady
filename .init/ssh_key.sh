#!/usr/bin/env sh

# Function to print usage
usage() {
    echo "Usage: $0 [-r]"
    echo "  -r    Forcefully overwrite the authorized_keys file with the new public key"
    exit 1
}

# Parse command line options
while getopts ":r" opt; do
    case ${opt} in
        r )
            FORCE_OVERWRITE=true
            ;;
        \? )
            usage
            ;;
    esac
done
shift $((OPTIND -1))

if [ -f /data/.profile ]; then
    . /data/.profile
fi

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

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 获取项目根目录（脚本目录的上级目录）
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_KEY_FILE="${PROJECT_ROOT}/pub/xiaoji.pub"

# 优先级：环境变量 > 项目目录 > /data挂载 > 网络下载
if [ -n "${SSHKEY}" ]; then
    echo "Using SSH public key from environment..."
    printf '%s\n' "${SSHKEY}" > "${PUBKeyFile}"
elif [ -f "${PROJECT_KEY_FILE}" ]; then
    echo "Using project public key..."
    cp "${PROJECT_KEY_FILE}" "${PUBKeyFile}" >/dev/null
elif [ -f /data/pub/xiaoji.pub ]; then
    echo "Using mounted public key..."
    cp /data/pub/xiaoji.pub "${PUBKeyFile}" >/dev/null
else
    echo "Downloading public key from mirror..."
    curl -sSL "${KEY_URL}" -o "${PUBKeyFile}"
fi

if [ "${FORCE_OVERWRITE}" = true ]; then
    # Forcefully overwrite authorized_keys
    cat "${PUBKeyFile}" > "$HOME/.ssh/authorized_keys"
else
    # Append the key only if it does not already exist
    if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
        cat "${PUBKeyFile}" > "$HOME/.ssh/authorized_keys"
    else
        AuthKeyStr=$(cat "$HOME/.ssh/authorized_keys")
        PUBKeyStr=$(awk '{$1=$1};1' < "${PUBKeyFile}")
        CompareResult=$(echo "${AuthKeyStr}" | grep "${PUBKeyStr}")
        [ "$CompareResult" = "" ] && {
            cat "${PUBKeyFile}" >> "$HOME/.ssh/authorized_keys"
        }
    fi
fi

chmod 600 "$HOME/.ssh/authorized_keys" >/dev/null

# 清理临时文件
[ -n "${PUBKeyFile}" ] && rm -rf "${PUBKeyFile}"

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

# Disable password login
echo "Disable password login"
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# Enable public key authentication
echo "Enable public key authentication"
sed -i.bak 's/^[#]\?[ ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
# Change MaxAuthTries to 10
echo "Change maxAuthTries"
sed -i 's/^[#]\?[ ]*MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config

# Restart the SSH service to apply the changes
if [ -n "$(command -v systemctl)" ]; then
    systemctl restart sshd
elif [ -n "$(command -v rc-service)" ]; then
    # Alpine Linux (OpenRC)
    rc-service sshd restart
else
    service sshd restart
    service ssh restart
fi
