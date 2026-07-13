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
├── scripts/            # 可单独执行的脚本
│   ├── install/        # 安装脚本
│   ├── configure/      # 配置脚本
│   └── tools/          # 工具脚本
├── lib/                # Shell 函数库
│   └── common.sh       # 通用函数
├── config/             # 配置和模板文件
├── Dockerfiles/        # Docker 配置文件示例
├── web/                # Web 配置示例
├── pub/                # 公钥目录（需用户自行替换）
├── init.sh             # 主初始化脚本入口
├── .ezenv              # 运行时环境变量配置
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
git clone https://github.com/benzBrake/VPSReady /data
cd /data

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

### 跳过 SSH 公钥安装

保留 SSH 配置和端口处理，但不新增或更新 `authorized_keys`：

```bash
NOT_INSTALL_SSH_KEY=true ./init.sh
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

### Docker 日志轮转配置

独立配置 Docker 容器日志轮转，无需重新安装 Docker：

```bash
# 下载并运行脚本
sh -c "$(curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_logs.sh" -o -)"

# 或使用环境变量自定义配置
DOCKER_LOG_MAX_SIZE=50m DOCKER_LOG_MAX_FILE=5 sh -c "$(curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_logs.sh" -o -)"
```

**环境变量：**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_LOG_MAX_SIZE` | `10m` | 单个日志文件最大大小 |
| `DOCKER_LOG_MAX_FILE` | `3` | 保留的日志文件数量 |
| `DOCKER_LOG_DRIVER` | `json-file` | 日志驱动类型 |

### 安装 SSH 公钥

```bash
bash -c "$(curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_key.sh" -o -)"
```

默认只安装或更新 `authorized_keys`，不会修改 `sshd_config`。

**可选参数：**

| 参数 | 说明 |
|------|------|
| `-k` | 显式安装或更新公钥（`NOT_INSTALL_SSH_KEY=true` 时仍跳过） |
| `-r` | 覆盖现有 `authorized_keys` |
| `-P` | 设置 `PasswordAuthentication no` |
| `-A` | 设置 `PubkeyAuthentication yes` |
| `-M` | 设置 `MaxAuthTries 20` |
| `-S` | 修改完成后重启 SSH 服务 |
| `-b <repo_base_url>` | 指定仓库基地址，并自动拼出 `/pub/xiaoji.pub` |
| `-u <key_url>` | 直接指定公钥下载地址 |

例如：

```bash
curl -sSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_key.sh" | sh -s -- -k -P -A -M -S
```

如果脚本本身是通过 CDN 或镜像地址直接管道执行，公钥地址也要一并显式传入，因为 `curl | sh` 无法让脚本自动知道自己的来源 URL。例如 `jsdmirror`：

```bash
curl -sSL "https://cdn.jsdmirror.com/gh/benzBrake/VPSReady@main/scripts/configure/ssh_key.sh" | sh -s -- -k -b "https://cdn.jsdmirror.com/gh/benzBrake/VPSReady@main"
```

### 所有独立模块

所有 `scripts/` 下的脚本都可以单独执行。若使用仓库中的文件，先执行：

```bash
cd VPSReady
chmod +x init.sh scripts/install/*.sh scripts/configure/*.sh scripts/tools/*.sh
```

#### 安装模块

| 模块 | 本地执行 | 主要配置 |
|------|----------|----------|
| ACME SSL | `sh scripts/install/acme.sh` | `MIRROR`、`LET_MAIL` |
| Caddy | `sh scripts/install/caddy.sh` | `CADDY_*`、`DOWNLOAD_URL` |
| Docker | `sh scripts/install/docker.sh` | `DOCKER_*` |
| Glow | `sh scripts/install/glow.sh` | `GLOW_VERSION`、`GLOW_INSTALL_DIR`、`GLOW_MIRROR` |
| tcping | `sh scripts/install/tcping.sh` | `TCPING_VERSION`、`TCPING_INSTALL_DIR`、`TCPING_FORCE_REINSTALL` |
| Nginx | `sh scripts/install/nginx.sh` | 使用 `/data/web` 配置 |

远程执行示例：

```bash
curl -fsSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/docker.sh" | sh
```

安装 tcping：

```bash
curl -fsSL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/tcping.sh" | sh
```

默认从 GitHub Releases 网页解析最新版本，并按 Linux 系统架构下载对应资产，不使用 GitHub API。
可通过 `TCPING_VERSION` 指定版本、`TCPING_INSTALL_DIR` 指定安装目录，或设置 `TCPING_FORCE_REINSTALL=true` 强制重装。

#### 配置模块

| 模块 | 本地执行 | 主要参数或环境变量 |
|------|----------|-------------------|
| Docker 端口白名单 | `sh scripts/configure/docker_iptables.sh` | 按脚本提示配置白名单 |
| Docker 日志轮转 | `sh scripts/configure/docker_logs.sh` | `DOCKER_LOG_MAX_SIZE`、`DOCKER_LOG_MAX_FILE`、`DOCKER_LOG_DRIVER` |
| SSH 公钥 | `sh scripts/configure/ssh_key.sh -k` | `-r`、`-P`、`-A`、`-M`、`-S`、`-b`、`-u` |
| SSH 端口 | `sh scripts/configure/ssh_port.sh` | `NOT_CHANGE_SSH_PORT=true` 可跳过改端口 |

例如配置 Docker 日志：

```bash
DOCKER_LOG_MAX_SIZE=50m DOCKER_LOG_MAX_FILE=5 \
  sh scripts/configure/docker_logs.sh
```

#### 工具模块

| 模块 | 使用方式 |
|------|----------|
| 备份 | `sh scripts/tools/backup.sh` |
| Cloudflared 安装及命令转发 | `sh scripts/tools/cloudflared.sh [参数]` |
| Cloudflare Tunnel 多实例 | `sh scripts/tools/cloudflare_tunnel.sh [add|remove|list|start|stop|restart|status|temp]` |
| 查找大文件 | `. scripts/tools/find_large_files.sh && find_large_files [目录] [大小阈值MB]` |

工具模块的完整参数可以使用 `-h` 或直接不带参数运行查看。

`.ezenv` 是部署到 `/data/.ezenv` 的运行时环境文件，会将 `/data/scripts/tools` 加入 `PATH`，并加载 `/data/.ez/ez.bash`。不要把它当作可执行模块运行。

### Cloudflare Tunnel 多实例管理

`scripts/tools/cloudflare_tunnel.sh` 使用 Cloudflare Zero Trust 控制台生成的 tunnel token，管理多个相互独立的本机连接器。无参数运行时进入交互菜单，也可以使用子命令自动化操作：

```bash
# 进入交互菜单
/data/scripts/tools/cloudflare_tunnel.sh

# 安全地交互输入 token 并创建实例
/data/scripts/tools/cloudflare_tunnel.sh add blog

# 从文件读取 token，token 不会出现在进程参数中
/data/scripts/tools/cloudflare_tunnel.sh add api --token-file /root/api-tunnel-token

# 查看并管理实例
/data/scripts/tools/cloudflare_tunnel.sh list
/data/scripts/tools/cloudflare_tunnel.sh status blog
/data/scripts/tools/cloudflare_tunnel.sh stop blog
/data/scripts/tools/cloudflare_tunnel.sh start blog
/data/scripts/tools/cloudflare_tunnel.sh restart blog

# 删除本机实例，需要确认；自动化脚本可以使用 --force
/data/scripts/tools/cloudflare_tunnel.sh remove blog
/data/scripts/tools/cloudflare_tunnel.sh remove api --force

# 创建退出后即失效的 Quick Tunnel
/data/scripts/tools/cloudflare_tunnel.sh temp http://127.0.0.1:8080
```

如果系统安装了 Docker，脚本会为每条 tunnel 创建一个使用 `unless-stopped` 重启策略的独立容器。Docker 已安装但 daemon 不可用时，脚本会报错，不会混用原生模式。如果没有安装 Docker，Debian/Ubuntu 使用 systemd，Alpine 使用 OpenRC，并配置开机启动。

实例数据保存在 `/data/cloudflared/tunnels/<name>`。token 文件权限为 `600`，Docker 容器和系统服务均通过 token 文件启动，不把 token 写入命令参数。实例名称只允许小写字母、数字、下划线和连字符。

`remove` 只停止并删除本机容器或服务以及本地 token，不会删除 Cloudflare 控制台中的 tunnel、DNS、SSL/TLS 或其他远端配置。若创建或启动失败，可以在修复 Docker 或系统服务问题后运行 `start <name>` 重试；需要彻底回滚时运行 `remove <name> --force`。

### Shell 文件命名

- 文件名统一使用小写字母和下划线（`snake_case`），不使用连字符。
- `scripts/install/`、`scripts/configure/` 和 `scripts/tools/` 表达脚本类别，文件名优先直接描述对象，例如 `docker_logs.sh`。
- 只有需要区分操作时才使用“动作 + 对象”，例如 `find_large_files.sh`。
- 新增或修改的 `.sh` 文件必须保留可执行权限（Git 模式 `100755`）。

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
