#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
EZ_DATA="${EZ_DATA:-$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)}"
ACME_HOME="${EZ_DATA}/.acme.sh"

if [ -z "${LET_MAIL}" ]; then
    LET_MAIL="webmaster@woai.ru"
fi

install_cron() {
    # Check the Linux distribution
    if [ -f /etc/redhat-release ]; then
        # CentOS
        echo "Installing cron on CentOS..."
        yum install -y cronie
        systemctl enable crond
        systemctl start crond
    elif [ -f /etc/debian_version ]; then
        # Debian or Ubuntu
        echo "Installing cron on Debian/Ubuntu..."
        apt-get update
        apt-get install -y cron
        systemctl enable cron
        systemctl start cron
    elif [ -f /etc/alpine-release ]; then
        # Alpine
        echo "Installing cron on Alpine..."
        apk add --no-cache cron
        rc-update add cron
        rc-service cron start
    else
        echo "Unsupported Linux distribution."
        exit 1
    fi
    echo "Cron installed successfully."
}
install_cron
if [ -d "${ACME_HOME}" ]; then
    if [ ! -f "$HOME/.bashrc" ]; then
        : > "$HOME/.bashrc"
    fi
    if ! grep -F ". \"${ACME_HOME}/acme.sh.env\"" "$HOME/.bashrc" >/dev/null 2>&1; then
        echo ". \"${ACME_HOME}/acme.sh.env\"" >>"$HOME/.bashrc"
    fi
    (crontab -u root -l | grep -v "acme.sh") | crontab -u root -
    crontab -u root -l 2>/dev/null | { cat; echo "0 0 * * * \"${ACME_HOME}\"/acme.sh --cron --home \"${ACME_HOME}\" > /dev/null"; } | crontab -u root -
else
    git clone "${MIRROR}https://github.com/acmesh-official/acme.sh.git" /tmp/acme.sh
    cd /tmp/acme.sh
    ./acme.sh --install  \
    --home "${ACME_HOME}" \
    --accountemail  "${LET_MAIL}"
    rm -rf /tmp/acme.sh
fi
. "${ACME_HOME}/acme.sh.env"
"${ACME_HOME}/acme.sh" --set-default-ca --server letsencrypt
