#!/usr/bin/env sh
# Verify Docker installer source selection with mocked package managers.

set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
SYSTEM_PATH="${PATH}"

cleanup() {
    rm -rf "${TEST_DIR}"
}

trap cleanup EXIT HUP INT TERM

mkdir -p "${TEST_DIR}/apt-bin" "${TEST_DIR}/apk-bin"
mkdir -p "${TEST_DIR}/apt/keyrings" "${TEST_DIR}/apt/sources"
mkdir -p "${TEST_DIR}/remote"

tee "${TEST_DIR}/os-release" > /dev/null <<'EOF'
ID=debian
VERSION_CODENAME=bookworm
EOF

TEST_COMMAND_LOG="${TEST_DIR}/commands.log"
export TEST_COMMAND_LOG

tee "${TEST_DIR}/apt-bin/apt-get" > /dev/null <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "${TEST_COMMAND_LOG}"
EOF

tee "${TEST_DIR}/apt-bin/dpkg" > /dev/null <<'EOF'
#!/usr/bin/env sh
printf '%s\n' amd64
EOF

tee "${TEST_DIR}/apt-bin/systemctl" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

tee "${TEST_DIR}/apt-bin/sleep" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

tee "${TEST_DIR}/apt-bin/curl" > /dev/null <<'EOF'
#!/usr/bin/env sh
OUTPUT=""
DOWNLOAD_SOURCE_URL=""

while [ "$#" -gt 0 ]; do
    if [ "${1}" = -o ]; then
        OUTPUT="${2}"
        shift 2
        continue
    fi
    DOWNLOAD_SOURCE_URL="${1}"
    shift
done

if printf '%s\n' "${DOWNLOAD_SOURCE_URL}" | grep -q '/lib/docker_daemon.sh'; then
    tee "${OUTPUT}" > /dev/null <<'LIBRARY'
DOCKER_REGION=${DOCKER_REGION:-global}
configure_docker_daemon() {
    return 0
}
LIBRARY
elif [ "${FAKE_CURL_MODE:-gpg}" = installer ]; then
    tee "${OUTPUT}" > /dev/null <<'INSTALLER'
#!/usr/bin/env sh
printf '%s\n' "$@" > "${TEST_GLOBAL_ARGS}"
INSTALLER
else
    printf '%s' 'fake Docker GPG key' > "${OUTPUT}"
fi
EOF

tee "${TEST_DIR}/apk-bin/apk" > /dev/null <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "${TEST_COMMAND_LOG}"
EOF

tee "${TEST_DIR}/apk-bin/systemctl" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

tee "${TEST_DIR}/apk-bin/sleep" > /dev/null <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

chmod 755 "${TEST_DIR}"/*-bin/*

PATH="${TEST_DIR}/apt-bin:${SYSTEM_PATH}"
export PATH

DOCKER_REGION=cn \
DOCKER_INSTALL_MIRROR=AzureChinaCloud \
DOCKER_OS_RELEASE_FILE="${TEST_DIR}/os-release" \
DOCKER_APT_KEYRING_DIR="${TEST_DIR}/apt/keyrings" \
DOCKER_APT_SOURCE_FILE="${TEST_DIR}/apt/sources/docker.list" \
DOCKER_DISABLE_LOG_CONFIG=true \
sh "${ROOT_DIR}/scripts/install/docker.sh"

grep -F "https://mirror.azure.cn/docker-ce/linux/" "${TEST_DIR}/apt/sources/docker.list"
grep -F "install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "${TEST_COMMAND_LOG}"

: > "${TEST_COMMAND_LOG}"
TEST_GLOBAL_ARGS="${TEST_DIR}/global.args"
export TEST_GLOBAL_ARGS

FAKE_CURL_MODE=installer \
DOCKER_REGION=global \
DOCKER_INSTALL_MIRROR=Aliyun \
DOCKER_INSTALLER_URL=https://installer.example \
DOCKER_DISABLE_LOG_CONFIG=true \
sh "${ROOT_DIR}/scripts/install/docker.sh"

grep -Fx -- --mirror "${TEST_GLOBAL_ARGS}"
grep -Fx Aliyun "${TEST_GLOBAL_ARGS}"

cp "${ROOT_DIR}/scripts/install/docker.sh" "${TEST_DIR}/remote/docker.sh"
cp "${ROOT_DIR}/scripts/configure/docker_logs.sh" "${TEST_DIR}/remote/docker_logs.sh"

FAKE_CURL_MODE=installer \
DOCKER_REGION=global \
DOCKER_INSTALLER_URL=https://installer.example \
DOCKER_DISABLE_LOG_CONFIG=true \
sh "${TEST_DIR}/remote/docker.sh"

[ -f "${TEST_GLOBAL_ARGS}" ]

FAKE_CURL_MODE=installer DOCKER_REGION=global sh "${TEST_DIR}/remote/docker_logs.sh"

: > "${TEST_COMMAND_LOG}"
PATH="${TEST_DIR}/apk-bin:${SYSTEM_PATH}"
export PATH

DOCKER_REGION=cn \
DOCKER_DISABLE_LOG_CONFIG=true \
sh "${ROOT_DIR}/scripts/install/docker.sh"

grep -F "add --no-cache docker" "${TEST_COMMAND_LOG}"
grep -F "add --no-cache docker-cli-compose" "${TEST_COMMAND_LOG}"

printf '%s\n' 'Docker installation path tests passed'
