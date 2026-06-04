#!/usr/bin/env sh
[ -f "/data/.profile" ] && . /data/.profile
[ -f "/data/.utils/common.sh" ] && . /data/.utils/common.sh
if [ -e "/etc/ssh/sshd_config" ]; then
    # 备份SSH配置
    info "Backup SSH config"
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    if [ -f "/data/.init/ssh_key.sh" ]; then
        GH_MIRROR="${GH_MIRROR}" sh /data/.init/ssh_key.sh -k -A -M
    else
        curl -sSL "${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/ssh_key.sh" | KEY_URL="${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/pub/xiaoji.pub" sh -s -- -k -A -M
    fi
    # 仅公钥登录
    info "Enable only login with public key"
    if grep -i '^PasswordAuthentication.*' /etc/ssh/sshd_config >/dev/null; then
        sed -i "s@^PasswordAuthentication.*@PasswordAuthentication no@" /etc/ssh/sshd_config
    else
        if grep -i '^#PasswordAuthentication.*' /etc/ssh/sshd_config >/dev/null; then
            sed -i "s@^#PasswordAuthentication.*@&\nPasswordAuthentication no@" /etc/ssh/sshd_config
        else
            echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
        fi
    fi
    # SSH端口
    if [ "$NOT_CHANGE_SSH_PORT" != "true" ]; then
        info "Change SSH port to 33022"
        if grep -Eq '^[[:space:]]*[pP][oO][rR][tT][[:space:]]+' /etc/ssh/sshd_config; then
            sed -i 's@^[[:space:]]*[pP][oO][rR][tT][[:space:]].*@Port 33022@' /etc/ssh/sshd_config
        else
            if grep -Eq '^[[:space:]]*#[[:space:]]*[pP][oO][rR][tT][[:space:]]+' /etc/ssh/sshd_config; then
                sed -i '/^[[:space:]]*#[[:space:]]*[pP][oO][rR][tT][[:space:]][[:space:]]*/a Port 33022' /etc/ssh/sshd_config
            else
                echo "Port 33022" >>/etc/ssh/sshd_config
            fi

        fi
    fi
    # 重启SSH服务
    info "Restart SSH Service"
    if [ -n "$(command -v systemctl)" ]; then
        if systemctl restart sshd; then
            info "Remove SSH Config Backup"
            rm -f /etc/ssh/sshd_config.bak >/dev/null
        else
            err "Modify SSH config Failed."
            info "Restoring SSH Config..."
            rm -f /etc/ssh/sshd_config >/dev/null
            mv -f /etc/ssh/sshd_config.bak /etc/ssh/sshd_config >/dev/null
        fi
    elif [ -n "$(command -v rc-service)" ]; then
        # Alpine Linux (OpenRC)
        if rc-service sshd restart; then
            info "Remove SSH Config Backup"
            rm -f /etc/ssh/sshd_config.bak >/dev/null
        else
            err "Modify SSH config Failed."
            info "Restoring SSH Config..."
            rm -f /etc/ssh/sshd_config >/dev/null
            mv -f /etc/ssh/sshd_config.bak /etc/ssh/sshd_config >/dev/null
        fi
    else
        service sshd restart
        service ssh restart
    fi
else
    warn "Do not support none OpenSSH Server!"
fi
