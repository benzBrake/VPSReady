# VPSReady

VPS 自动化初始化脚本项目，用于快速配置新 VPS 环境。

## 项目概述

VPSReady 是一套用于 Debian/Ubuntu/Alpine Linux 的 VPS 初始化脚本集合。它会自动完成 SSH 安全配置、Docker 环境搭建、Nginx 安装、SSL 证书申请等常见 VPS 初始化任务，让新 VPS 快速投入使用。

### 核心功能

- **SSH 安全配置**: 自动修改 SSH 端口、配置公钥认证
- **Docker 环境**: 根据内存自动判断是否安装 Docker 和 Docker Compose
- **Nginx 安装**: 自动安装并配置 Nginx
- **SSL 证书**: 集成 acme.sh 自动申请 Let's Encrypt 证书
- **BBR 优化**: 自动启用 TCP BBR 拥塞控制算法
- **系统优化**: 安装常用工具包、创建系统用户、配置环境

<!-- AUTO:tech-stack -->
## 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| 脚本语言 | POSIX Shell | - |
| 支持系统 | Debian/Ubuntu/Alpine | - |
| 容器化 | Docker | Latest |
| Web 服务器 | Nginx | Latest |
| SSL 工具 | acme.sh | Latest |
| 同步工具 | Rclone | Latest |
<!-- /AUTO:tech-stack -->

<!-- AUTO:directory -->
## 项目结构

```
VPSReady/
├── .init/              # 初始化模块脚本
│   ├── acme.sh        # ACME SSL 证书申请
│   ├── docker.sh      # Docker 安装配置
│   ├── nginx.sh       # Nginx 安装配置
│   ├── ssh_key.sh     # SSH 公钥配置
│   └── ssh_port.sh    # SSH 端口修改
├── .utils/             # 工具函数库
│   ├── backup.sh      # 备份工具
│   └── common.sh      # 通用函数
├── Dockerfiles/        # Docker 配置文件示例
├── web/                # Web 配置示例
├── pub/                # 公钥目录（需用户自行替换）
├── init.sh             # 主初始化脚本入口
├── .ezenv              # 环境变量配置
└── .docker-compose.yml.demo  # Docker Compose 示例
```
<!-- /AUTO:directory -->

<!-- AUTO:quick-start -->
## 快速开始

### 环境要求

- **操作系统**: Debian 9+, Ubuntu 18.04+, Alpine 3.x
- **权限**: root 用户或 sudo 权限
- **网络**: 可访问 GitHub（或使用镜像）

### 基础安装

```bash
# 1. 安装 Git
# Debian/Ubuntu
apt-get update && apt-get -y install git

# Alpine
apk update && apk add git

# 2. 克隆项目
git clone https://github.com/benzBrake/VPSReady /data/VPSReady
cd /data/VPSReady

# 3. 执行初始化
chmod +x ./init.sh
./init.sh
```
<!-- /AUTO:quick-start -->

## 高级配置

### 自定义 SSH 公钥

```bash
SSHKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... your-key-comment" ./init.sh
```

### 不修改 SSH 端口

```bash
NOT_CHANGE_SSH_PORT=true ./init.sh
```

### 不安装 Docker

```bash
NOT_INSTALL_DOCKER=true ./init.sh
```

### 自定义 Let's Encrypt 邮箱

```bash
LET_MAIL=your@email.com ./init.sh
```

### 使用 GitHub 镜像

```bash
MIRROR=https://ghmirror.pp.ua ./init.sh
```

### 多参数组合

```bash
NOT_CHANGE_SSH_PORT=true LET_MAIL=your@email.com SSHKEY="ssh-rsa AAAA..." ./init.sh
```

### Docker 日志轮转配置

脚本会自动为 Docker 配置日志轮转策略，防止容器日志无限增长占用磁盘空间。

#### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_LOG_MAX_SIZE` | `10m` | 单个日志文件最大大小（如：`10m`, `50m`, `100m`） |
| `DOCKER_LOG_MAX_FILE` | `3` | 保留的日志文件数量（如：`3`, `5`, `10`） |
| `DOCKER_LOG_DRIVER` | `json-file` | 日志驱动类型 |
| `DOCKER_DISABLE_LOG_CONFIG` | `false` | 设为 `true` 跳过日志配置 |

#### 配置示例

```bash
# 自定义日志大小和文件数量
DOCKER_LOG_MAX_SIZE=50m DOCKER_LOG_MAX_FILE=5 ./init.sh

# 禁用自动日志配置
DOCKER_DISABLE_LOG_CONFIG=true ./init.sh
```

#### 验证配置

```bash
# 查看配置文件
cat /etc/docker/daemon.json

# 应该看到类似输出：
# {
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "10m",
#     "max-file": "3"
#   }
# }

# 测试日志轮转
docker run -d --name log-test nginx:alpine
# 生成一些日志后检查
docker logs log-test
```

#### 故障排查

如果日志配置出现问题，可以手动恢复：

```bash
# 如果有备份文件
sudo mv /etc/docker/daemon.json.bak /etc/docker/daemon.json

# 重启 Docker
sudo systemctl restart docker
```

## 单独运行模块

### 安装 SSH 公钥

```bash
bash -c "$(curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/.init/ssh_key.sh" -o -)"
```

### 其他模块

所有独立脚本都在 `.init/` 目录下，可根据需要单独执行。

## 玩 VPS 前置

### IPv6 Only VPS 解决方案

如果使用只有 IPv6 的 VPS（无 IPv4 的 NAT），无法直接访问 GitHub：

#### 方案 1: 使用 NAT64

```bash
cp /etc/resolv.conf /etc/resolv.conf.bak
rm -f /etc/resolv.conf
vim /etc/resolv.conf
```

添加以下内容：
```
nameserver 2001:67c:27e4:15::6411
nameserver 2001:67c:27e4::64
nameserver 2a03:7900:2:0:31:3:104:161
```

#### 方案 2: 使用 WARP

```bash
MIRROR=https://ghmirror.pp.ua bash <(curl -fsSL https://ghmirror.pp.ua/https://github.com/benzBrake/warp.sh/raw/main/warp.sh) 4
```

## 安全注意事项

⚠️ **克隆后务必更换 `pub/` 目录下的公钥**

## 许可证

本项目采用开源许可证，详见 [LICENSE](./LICENSE) 文件。
