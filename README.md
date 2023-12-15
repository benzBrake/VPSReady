# VPSReady
VPS初始化脚本
因为 CentOS 被切换到 Stream，估计以后写SHELL都不考虑RHEL系了。

ℹ克隆脚本以后记得更换pub目录下的公钥

## 脚本功能说明

1. 默认情况下会修改 SSH 端口为 33022，暂时不支持自定义端口
2. 默认情况下会安装 curl ca-certificates vim unzip ftp openssl bash 等软件包
3. 脚本会根据内存判断是否安装 Docker/Docker-Compose 和 MySQL 命令行客户端 (低于512MB不安装)
4. 增加 MySQL 用户 (1001:1001)，WWW 用户 (1002:1002)
5. 安装仓库内的 VIM 配置文件
6. 安装 .ez-bash
7. 安装 Rclone
8. 自动启用 BBR
9. 安装 acme.sh

## 玩 VPS 前置

如果是贪便宜购入了只有 IPv6 的小鸡（不包括有 IPv4 的 NAT），那么你是无法直接安装存储在 Github 上的脚本的，因为 Github 没有 IPv6 地址。

解决办法有两个一个是使用 NAT64 服务，另一个是使用 Clouflare 提供的 WARP

### 使用 NAT64 服务

```
cp /etc/resolv.conf /etc/resolv.conf.bak
rm -f /etc/resolv.conf
vim /etc/resolv.conf

nameserver 2001:67c:27e4:15::6411
nameserver 2001:67c:27e4::64

nameserver 2a03:7900:2:0:31:3:104:161
```

### 使用 WARP

自动配置 WARP WireGuard IPv4 网络（IPv4 出站流量走 WARP 网络）

```shell
MIRROR=https://ghmirror.pp.ua bash <(curl -fsSL https://ghmirror.pp.ua/https://github.com/benzBrake/warp.sh/raw/main/warp.sh) 4
```

> PS: 上边使用的 https://ghmirror.pp.ua 是一个 GitHub 镜像，你可以自行部署 https://github.com/benzBrake/gh-proxy/

## 安装脚本

### 安装 Git

#### Debian/Ubuntu

```shell
apt-get update && apt-get -y install git
```
#### Alpine

```shell
apk update && apk add git
```

### 克隆脚本

```shell
git clone https://github.com/benzBrake/VPSReady /data
```

## 使用

### 初始化 VPS
```shell
cd /data
chmod +x ./init.sh
./init.sh
```

### 如果不需要修改 SSH 端口

```shell
NOT_CHANGE_SSH_PORT=true ./init.sh
```

### 自定义 LET SSL 的邮箱

```shell
LET_MAIL=bbb@ccc.com ./init.sh
```

### 多个参数

```shell
NOT_CHANGE_SSH_PORT=true LET_MAIL=bbb@ccc.com ./init.sh
```

## 其他 GitHub 镜像

https://github.moeyy.xyz/

## 单独运行其中的初始化脚本

### 安装 SSH 公钥

```
bash -c "$(curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/ssh_key.sh" -o -)"
```



## 其他 VPS 一键脚本

利用上边初始化 VPS 如有需要，也可以安装的脚本。

