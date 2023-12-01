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

如果不 VPS 支持 IPv4，使用 ghproxy 镜像网站

```
git clone https://ghmirror.pp.ua/https://github.com/benzBrake/VPSReady /data
```

## 使用

### 初始化 VPS
```shell
cd /data
chmod +x /init.sh
./init.sh
```

### 如果 VPS 不支持 IPv4

使用 ghproxy 镜像网站

```shell
cd /data
chmod +x ./init.sh
MIRROR=https://ghmirror.pp.ua ./init.sh
```

### 如果不需要修改 SSH 端口

```shell
NOT_CHANGE_SSH_PORT=true ./init.sh
```

## 其他 GitHub 镜像

https://github.moeyy.xyz/

## 其他 VPS 一键脚本

利用上边初始化 VPS 如有需要，也可以安装的脚本。

### 安装 Wrap

```

```
