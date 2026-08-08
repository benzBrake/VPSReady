#!/usr/bin/env sh
# Verify tcping GitHub URLs honor the configured mirror.

set -eu

ROOT_DIR=$(cd "$(dirname "${0}")/.." && pwd)
FUNCTIONS_FILE=$(mktemp)

cleanup() {
    rm -f "${FUNCTIONS_FILE}"
}

trap cleanup EXIT HUP INT TERM

sed '/^main "\$@"$/d' "${ROOT_DIR}/scripts/install/tcping.sh" > "${FUNCTIONS_FILE}"
. "${FUNCTIONS_FILE}"

info() {
    :
}

err() {
    :
}

TCPING_REPO=owner/repo
TCPING_VERSION=
TCPING_OS=linux
TCPING_ARCH=amd64
GH_MIRROR=https://ghmirror.example/
MIRROR=
EXPECTED_RELEASE_URL="https://ghmirror.example/https://github.com/owner/repo/releases"
EXPECTED_API_URL="https://ghmirror.example/https://api.github.com/repos/owner/repo/releases/tags/v1.2.3"
EXPECTED_ASSET_URL="https://ghmirror.example/https://github.com/owner/repo/releases/download/v1.2.3/tcping-linux-amd64-v1.2.3.tar.gz"

curl() {
    case "${2}" in
        "${EXPECTED_RELEASE_URL}")
            printf '%s\n' '<a href="/owner/repo/releases/tag/v1.2.3">v1.2.3</a>'
            ;;
        "${EXPECTED_API_URL}")
            printf '%s\n' '{"browser_download_url":"https://github.com/owner/repo/releases/download/v1.2.3/tcping-linux-amd64-v1.2.3.tar.gz"}'
            ;;
        *)
            return 1
            ;;
    esac
}

get_release_page
[ "${TCPING_VERSION}" = v1.2.3 ]
find_asset_url
[ "${TCPING_ASSET_URL}" = "${EXPECTED_ASSET_URL}" ]

unset GH_MIRROR
MIRROR=https://mirror.example
[ "$(get_github_url "https://github.com/owner/repo/releases")" = "https://mirror.example/https://github.com/owner/repo/releases" ]

printf '%s\n' 'tcping GitHub mirror tests passed'
