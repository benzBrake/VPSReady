#!/bin/sh

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
if [ -d "/data/.acme.sh" ]; then
    grep .acme.sh/acme.sh.env ~/.bashrc > /dev/null
    if [ $? -ne 0 ]; then
        echo ". \"/data/.acme.sh/acme.sh.env\"" > ~/.bashrc
    fi
    (crontab -u root -l | grep -v "acme.sh") | crontab -u root -
    crontab -u root -l 2>/dev/null | { cat; echo "0 0 * * * \"/data/.acme.sh\"/acme.sh --cron --home \"/data/.acme.sh\" > /dev/null"; } | crontab -u root -
else
    git clone "${MIRROR}https://github.com/acmesh-official/acme.sh.git" /tmp/acme.sh
    cd /tmp/acme.sh
    ./acme.sh --install  \
    --home /data/.acme.sh \
    --accountemail  "${LET_MAIL}"
    rm -rf /tmp/acme.sh
fi
. "/data/.acme.sh/acme.sh.env"
/data/.acme.sh/acme.sh --set-default-ca --server letsencrypt