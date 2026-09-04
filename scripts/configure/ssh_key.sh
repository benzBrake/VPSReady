#!/usr/bin/env sh

usage() {
    echo "Usage: $0 [-k] [-r] [-P] [-A] [-M] [-S] [-b repo_base_url] [-u key_url]"
    echo "  -k    Install or update the authorized_keys file (default behavior)"
    echo "  -r    Forcefully overwrite the authorized_keys file with the new public key"
    echo "  -P    Set PasswordAuthentication to no"
    echo "  -A    Set PubkeyAuthentication to yes"
    echo "  -M    Set MaxAuthTries (default: 15, or MAX_AUTH_TRIES)"
    echo "  -S    Restart the SSH service after updating sshd_config"
    echo "  -b    Set repository base URL, used to derive pub/xiaoji.pub"
    echo "  -u    Set public key download URL directly"
    exit 1
}

INSTALL_KEY=true
FORCE_OVERWRITE=false
DISABLE_PASSWORD_LOGIN=false
ENABLE_PUBKEY_AUTH=false
SET_MAX_AUTH_TRIES=false
RESTART_SSH=false
REPO_BASE_URL="${REPO_BASE_URL}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
EZ_DATA="${EZ_DATA:-$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)}"

# 使用 curl 或 Alpine BusyBox wget 下载文件
download_file() {
    DOWNLOAD_SOURCE_URL="${1}"
    DOWNLOAD_DESTINATION="${2}"
    DOWNLOAD_QUIET="${3:-false}"

    if [ "${DOWNLOAD_DESTINATION}" = /dev/null ] || [ "${DOWNLOAD_QUIET}" = true ]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "${DOWNLOAD_SOURCE_URL}" -o "${DOWNLOAD_DESTINATION}"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "${DOWNLOAD_DESTINATION}" "${DOWNLOAD_SOURCE_URL}"
        else
            echo "Neither curl nor wget is available" >&2
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        curl -fL "${DOWNLOAD_SOURCE_URL}" -o "${DOWNLOAD_DESTINATION}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${DOWNLOAD_DESTINATION}" "${DOWNLOAD_SOURCE_URL}"
    else
        echo "Neither curl nor wget is available" >&2
        return 1
    fi
}

trim_trailing_slash() {
    printf '%s' "$1" | sed 's:/*$::'
}

ensure_sshd_option() {
    option_name="$1"
    option_value="$2"

    if grep -Eq "^[[:space:]]*#?[[:space:]]*${option_name}[[:space:]]+" /etc/ssh/sshd_config; then
        sed -i "s@^[[:space:]]*#\\?[[:space:]]*${option_name}[[:space:]].*@${option_name} ${option_value}@" /etc/ssh/sshd_config
    else
        printf '%s %s\n' "${option_name}" "${option_value}" >>/etc/ssh/sshd_config
    fi
}

restart_ssh_service() {
    if [ -n "$(command -v systemctl)" ]; then
        systemctl restart sshd
    elif [ -n "$(command -v rc-service)" ]; then
        rc-service sshd restart
    else
        service sshd restart
        service ssh restart
    fi
}

while getopts ":krPAMSb:u:" opt; do
    case ${opt} in
        k )
            INSTALL_KEY=true
            ;;
        r )
            FORCE_OVERWRITE=true
            ;;
        P )
            DISABLE_PASSWORD_LOGIN=true
            ;;
        A )
            ENABLE_PUBKEY_AUTH=true
            ;;
        M )
            SET_MAX_AUTH_TRIES=true
            ;;
        S )
            RESTART_SSH=true
            ;;
        b )
            REPO_BASE_URL="${OPTARG}"
            ;;
        u )
            KEY_URL="${OPTARG}"
            ;;
        \? )
            usage
            ;;
    esac
done
shift $((OPTIND -1))

if [ -f "${EZ_DATA}/.profile" ]; then
    . "${EZ_DATA}/.profile"
fi

if [ "${NOT_INSTALL_SSH_KEY}" = true ]; then
    INSTALL_KEY=false
fi

if [ -n "${REPO_BASE_URL}" ]; then
    REPO_BASE_URL="$(trim_trailing_slash "${REPO_BASE_URL}")"
fi

if [ -z "${KEY_URL}" ]; then
    if [ -n "${REPO_BASE_URL}" ]; then
        KEY_URL="${REPO_BASE_URL}/pub/xiaoji.pub"
    else
        KEY_URL="${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/pub/xiaoji.pub"
    fi
fi

randomNum() {
    command -v shuf >/dev/null && shuf -i 100000-999999 -n 1 || jot -r 1 100000 999999
}

if [ "${INSTALL_KEY}" = true ]; then
    echo "Install public key"
    mkdir -p /tmp "$HOME/.ssh" >/dev/null
    PUBKeyFile="/tmp/$(randomNum).pub"
    while :; do
        echo >/dev/null
        [ ! -f "${PUBKeyFile}" ] && break
        PUBKeyFile="/tmp/$(randomNum).pub"
    done

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    PROJECT_KEY_FILE="${PROJECT_ROOT}/pub/xiaoji.pub"

    # 优先级：环境变量 > 项目目录 > EZ_DATA 挂载 > 网络下载
    if [ -n "${SSHKEY}" ]; then
        echo "Using SSH public key from environment..."
        printf '%s\n' "${SSHKEY}" > "${PUBKeyFile}"
    elif [ -f "${PROJECT_KEY_FILE}" ]; then
        echo "Using project public key..."
        cp "${PROJECT_KEY_FILE}" "${PUBKeyFile}" >/dev/null
    elif [ -f "${EZ_DATA}/pub/xiaoji.pub" ]; then
        echo "Using mounted public key..."
        cp "${EZ_DATA}/pub/xiaoji.pub" "${PUBKeyFile}" >/dev/null
    else
        echo "Downloading public key from mirror..."
        if ! download_file "${KEY_URL}" "${PUBKeyFile}" || [ ! -s "${PUBKeyFile}" ]; then
            echo "Failed to download public key" >&2
            rm -f "${PUBKeyFile}"
            exit 1
        fi
    fi

    if [ "${FORCE_OVERWRITE}" = true ]; then
        cat "${PUBKeyFile}" > "$HOME/.ssh/authorized_keys"
    else
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

    [ -n "${PUBKeyFile}" ] && rm -rf "${PUBKeyFile}"
fi

if [ "${DISABLE_PASSWORD_LOGIN}" = true ] || [ "${ENABLE_PUBKEY_AUTH}" = true ] || [ "${SET_MAX_AUTH_TRIES}" = true ] || [ "${RESTART_SSH}" = true ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run this script as root."
        exit 1
    fi
fi

if [ "${DISABLE_PASSWORD_LOGIN}" = true ]; then
    echo "Disable password login"
    ensure_sshd_option "PasswordAuthentication" "no"
fi

if [ "${ENABLE_PUBKEY_AUTH}" = true ]; then
    echo "Enable public key authentication"
    ensure_sshd_option "PubkeyAuthentication" "yes"
fi

if [ "${SET_MAX_AUTH_TRIES}" = true ]; then
    echo "Change maxAuthTries"
    ensure_sshd_option "MaxAuthTries" "${MAX_AUTH_TRIES:-15}"
fi

if [ "${RESTART_SSH}" = true ]; then
    restart_ssh_service
fi
