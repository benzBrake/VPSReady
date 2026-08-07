#!/usr/bin/env sh
# Verify Caddy release download URLs honor the configured GitHub mirror.

set -eu

ROOT_DIR=$(cd "$(dirname "${0}")/.." && pwd)
FUNCTIONS_FILE=$(mktemp)

cleanup() {
    rm -f "${FUNCTIONS_FILE}"
}

trap cleanup EXIT HUP INT TERM

sed -n '/^get_github_mirror_prefix()/,/^}/p' "${ROOT_DIR}/scripts/install/caddy.sh" > "${FUNCTIONS_FILE}"
sed -n '/^build_download_url()/,/^}/p' "${ROOT_DIR}/scripts/install/caddy.sh" >> "${FUNCTIONS_FILE}"

. "${FUNCTIONS_FILE}"

info() {
    :
}

warn() {
    :
}

err() {
    :
}

suc() {
    :
}

download_file() {
    DOWNLOAD_ATTEMPTS="${DOWNLOAD_ATTEMPTS}${DOWNLOAD_ATTEMPTS:+ }${1}"
    [ "${1}" = "${EXPECTED_DOWNLOAD_URL}" ]
}

CADDY_REPO=owner/repo
CADDY_VERSION=v1.2.3
CADDY_OS=linux
ARCH=amd64
DOWNLOAD_URL=
DOWNLOAD_ATTEMPTS=
EXPECTED_DOWNLOAD_URL="https://ghmirror.example/https://github.com/owner/repo/releases/download/v1.2.3/caddy-linux-amd64.tar.gz"
GH_MIRROR=https://ghmirror.example/
MIRROR=

build_download_url
[ "${DOWNLOAD_URL}" = "${EXPECTED_DOWNLOAD_URL}" ]
[ "${DOWNLOAD_ATTEMPTS}" = "${EXPECTED_DOWNLOAD_URL}" ]

DOWNLOAD_URL=
DOWNLOAD_ATTEMPTS=
EXPECTED_DOWNLOAD_URL="https://mirror.example/https://github.com/owner/repo/releases/download/v1.2.3/caddy-linux-amd64.tar.gz"
unset GH_MIRROR
MIRROR=https://mirror.example

build_download_url
[ "${DOWNLOAD_URL}" = "${EXPECTED_DOWNLOAD_URL}" ]
[ "${DOWNLOAD_ATTEMPTS}" = "${EXPECTED_DOWNLOAD_URL}" ]

printf '%s\n' 'Caddy download URL tests passed'
