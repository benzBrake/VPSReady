#!/usr/bin/env sh

# tcping 安装脚本

SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
if [ -f "${SCRIPT_DIR}/../../lib/common.sh" ]; then
    . "${SCRIPT_DIR}/../../lib/common.sh"
else
    info() { echo "[I] $*" >&2; }
    warn() { echo "[W] $*" >&2; }
    err() { echo "[E] $*" >&2; }
    suc() { echo "[S] $*" >&2; }
fi

TCPING_REPO="${TCPING_REPO:-cloverstd/tcping}"
TCPING_INSTALL_DIR="${TCPING_INSTALL_DIR:-/usr/local/bin}"
TCPING_VERSION="${TCPING_VERSION:-}"
TCPING_FORCE_REINSTALL="${TCPING_FORCE_REINSTALL:-false}"

detect_platform() {
    if [ "$(uname -s)" != "Linux" ]; then
        err "Only Linux is supported"
        return 1
    fi

    case "$(uname -m)" in
        x86_64|amd64)
            TCPING_ARCH="amd64"
            ;;
        aarch64|arm64)
            TCPING_ARCH="arm64"
            ;;
        armv7l|armv7)
            TCPING_ARCH="armhf"
            ;;
        *)
            err "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    TCPING_OS="linux"
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        if [ "${ID:-}" = "alpine" ]; then
            TCPING_OS="alpine-linux"
        fi
    fi

    info "Detected platform: ${TCPING_OS}/${TCPING_ARCH}"
}

ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    info "curl is not installed; installing it"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl || {
            err "Failed to install curl with apt-get"
            return 1
        }
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl || {
            err "Failed to install curl with apk"
            return 1
        }
    else
        err "curl is required, and no supported package manager was found"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        err "curl installation verification failed"
        return 1
    fi
}

get_release_page() {
    if [ -n "${TCPING_VERSION}" ]; then
        TCPING_RELEASE_PAGE="https://github.com/${TCPING_REPO}/releases/tag/${TCPING_VERSION}"
        return 0
    fi

    TCPING_RELEASES_PAGE=$(curl -fsSL "https://github.com/${TCPING_REPO}/releases") || {
        err "Failed to fetch GitHub Releases page"
        return 1
    }

    TCPING_VERSION=$(printf '%s\n' "${TCPING_RELEASES_PAGE}" |
        grep -o 'href="/[^/]*/[^/]*/releases/tag/[^"]*"' |
        sed -n 's#.*releases/tag/\([^"?]*\).*#\1#p' | head -n 1)
    if [ -z "${TCPING_VERSION}" ]; then
        err "Failed to parse the latest tcping version from the Releases page"
        return 1
    fi

    TCPING_RELEASE_PAGE="https://github.com/${TCPING_REPO}/releases/tag/${TCPING_VERSION}"
    info "Found tcping version: ${TCPING_VERSION}"
}

find_asset_url() {
    TCPING_RELEASE_API="https://api.github.com/repos/${TCPING_REPO}/releases/tags/${TCPING_VERSION}"
    TCPING_RELEASE_JSON=$(curl -fsSL "${TCPING_RELEASE_API}") || {
        err "Failed to fetch release metadata: ${TCPING_RELEASE_API}"
        return 1
    }

    TCPING_ASSET_URL=$(printf '%s\n' "${TCPING_RELEASE_JSON}" |
        sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        while IFS= read -r url; do
            name=$(printf '%s' "${url##*/}" | tr '[:upper:]' '[:lower:]')
            case "${TCPING_OS}/${TCPING_ARCH}" in
                alpine-linux/amd64)
                    case "${name}" in
                        # Alpine falls back to the generic Linux amd64 archive.
                        tcping-alpine-linux-amd64-*.tar.gz|\
                        tcping-alpine-linux-amd64-*.tgz|\
                        tcping-alpine-linux-amd64-*.zip|\
                        tcping-linux-amd64-*.tar.gz|\
                        tcping-linux-amd64-*.tgz|\
                        tcping-linux-amd64-*.zip)
                            ;;
                        *)
                            continue
                            ;;
                    esac
                    ;;
                linux/amd64)
                    case "${name}" in
                        tcping-linux-amd64-*.tar.gz|tcping-linux-amd64-*.tgz|tcping-linux-amd64-*.zip)
                            ;;
                        *)
                            continue
                            ;;
                    esac
                    ;;
                linux/arm64)
                    case "${name}" in
                        tcping-linux-arm64-*.tar.gz|tcping-linux-arm64-*.tgz|tcping-linux-arm64-*.zip|tcping-linux-aarch64-*.tar.gz|tcping-linux-aarch64-*.tgz|tcping-linux-aarch64-*.zip)
                            ;;
                        *)
                            continue
                            ;;
                    esac
                    ;;
                linux/armhf)
                    case "${name}" in
                        tcping-linux-armhf-*.tar.gz|tcping-linux-armhf-*.tgz|tcping-linux-armhf-*.zip|tcping-linux-armel-*.tar.gz|tcping-linux-armel-*.tgz|tcping-linux-armel-*.zip)
                            ;;
                        *)
                            continue
                            ;;
                    esac
                    ;;
                *)
                    continue
                    ;;
            esac
            echo "${url}"
            break
        done | head -n 1)

    if [ -z "${TCPING_ASSET_URL}" ]; then
        err "No tcping asset matches ${TCPING_OS}/${TCPING_ARCH}"
        return 1
    fi

    info "Selected asset: ${TCPING_ASSET_URL##*/}"
}

install_asset() {
    TCPING_TMP_DIR=$(mktemp -d) || {
        err "Failed to create temporary directory"
        return 1
    }
    TCPING_DOWNLOAD="${TCPING_TMP_DIR}/${TCPING_ASSET_URL##*/}"

    if ! curl -fsSL "${TCPING_ASSET_URL}" -o "${TCPING_DOWNLOAD}" || [ ! -s "${TCPING_DOWNLOAD}" ]; then
        err "Failed to download tcping asset"
        rm -rf "${TCPING_TMP_DIR}"
        return 1
    fi

    case "${TCPING_DOWNLOAD}" in
        *.tar.gz|*.tgz)
            tar -xzf "${TCPING_DOWNLOAD}" -C "${TCPING_TMP_DIR}" || {
                err "Failed to extract tcping archive"
                rm -rf "${TCPING_TMP_DIR}"
                return 1
            }
            ;;
        *.zip)
            command -v unzip >/dev/null 2>&1 || {
                err "unzip is required to extract the tcping archive"
                rm -rf "${TCPING_TMP_DIR}"
                return 1
            }
            unzip -q "${TCPING_DOWNLOAD}" -d "${TCPING_TMP_DIR}" || {
                err "Failed to extract tcping archive"
                rm -rf "${TCPING_TMP_DIR}"
                return 1
            }
            ;;
    esac

    TCPING_BINARY=$(find "${TCPING_TMP_DIR}" -type f -name tcping -perm -111 2>/dev/null | head -n 1)
    if [ -z "${TCPING_BINARY}" ]; then
        TCPING_BINARY=$(find "${TCPING_TMP_DIR}" -type f -name tcping 2>/dev/null | head -n 1)
    fi
    if [ -z "${TCPING_BINARY}" ]; then
        err "Downloaded asset does not contain a tcping binary"
        rm -rf "${TCPING_TMP_DIR}"
        return 1
    fi

    mkdir -p "${TCPING_INSTALL_DIR}" || {
        err "Failed to create ${TCPING_INSTALL_DIR}"
        rm -rf "${TCPING_TMP_DIR}"
        return 1
    }
    cp -f "${TCPING_BINARY}" "${TCPING_INSTALL_DIR}/tcping" &&
        chmod +x "${TCPING_INSTALL_DIR}/tcping" || {
        err "Failed to install tcping"
        rm -rf "${TCPING_TMP_DIR}"
        return 1
    }
    rm -rf "${TCPING_TMP_DIR}"
}

main() {
    if command -v tcping >/dev/null 2>&1 && [ "${TCPING_FORCE_REINSTALL}" != "true" ]; then
        info "tcping is already installed: $(command -v tcping)"
        return 0
    fi
    detect_platform || return 1
    ensure_curl || return 1
    get_release_page || return 1
    find_asset_url || return 1
    install_asset || return 1
    if ! "${TCPING_INSTALL_DIR}/tcping" --version >/dev/null 2>&1 &&
        ! "${TCPING_INSTALL_DIR}/tcping" -h >/dev/null 2>&1; then
        err "tcping installation verification failed"
        return 1
    fi
    suc "tcping installed to ${TCPING_INSTALL_DIR}/tcping"
}

main "$@"
