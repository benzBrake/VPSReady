# VPSReady
VPS初始化脚本
因为 CentOS 被切换到 Stream，估计以后写SHELL都不考虑RHEL系了。

ℹ克隆脚本以后记得更换pub目录下的公钥

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
git clone https://mirror.ghproxy.com/https://github.com/benzBrake/VPSReady /data
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
chmod +x /init.sh
MIRROR=https://mirror.ghproxy.com ./init.sh
```

### 如果不需要修改 SSH 端口

```shell
NOT_CHANGE_SSH_PORT=true ./init.sh
```

