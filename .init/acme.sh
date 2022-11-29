#!/bin/sh
if [ -d "/data/.acme.sh" ]; then
    grep .acme.sh/acme.sh.env ~/.bashrc > /dev/null
    if [ $? -ne 0 ]; then
        echo ". \"/data/.acme.sh/acme.sh.env\"" > ~/.bashrc
    fi
    (crontab -u root -l | grep -v "acme.sh") | crontab -u root -
    crontab -u root -l 2>/dev/null | { cat; echo "0 0 * * * \"/data/.acme.sh\"/acme.sh --cron --home \"/data/.acme.sh\" > /dev/null"; } | crontab -u root -
else
    git clone https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh
    cd /tmp/acme.sh
    ./acme.sh --install  \
    --home /data/.acme.sh \
    --accountemail  "webmaster@woai.ru"
    rm -rf /tmp/acme.sh
fi
/data/.acme.sh/acme.sh --set-default-ca --server letsencrypt