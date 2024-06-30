#!/bin/bash
source /data/.profile
if [ -e "/etc/ssh/sshd_config" ]; then
    # 备份SSH配置
    info "Backup SSH config"
    cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    if [ -f "/data/.init/ssh_key.sh" ]; then
        sh /data/.init/ssh_key.sh MIRROR="${GH_MIRROR}"
    else
        bash -c "$(curl -sSL "${GH_MIRROR}https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/ssh_key.sh" -o -)"
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
        RESULT=$(grep "^[pP][oO][rR][tT]\s*" /etc/ssh/sshd_config)
        if [ -n "$RESULT" ]; then
            sed -i "s#$RESULT#Port 33022#" /etc/ssh/sshd_config
        else
            RESULT=$(grep "^#[pP][oO][rR][tT]\s*" /etc/ssh/sshd_config)
            if [ -n "$RESULT" ]; then
                sed -i "/^#[pP][oO][rR][tT]\s*/a Port 33022" /etc/ssh/sshd_config
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
    else
        service sshd restart
        service ssh restart
    fi
else
    warn "Do not support none OpenSSH Server!"
fi