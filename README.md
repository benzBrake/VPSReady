# VPSReady

VPS 自动化初始化脚本项目，用于快速配置新 VPS 环境。

## 项目概述

VPSReady 是一套用于 Debian/Ubuntu/Alpine Linux 的 VPS 初始化脚本集合。它会自动完成 SSH 安全配置、Docker 环境搭建、Nginx 或 Caddy 安装、SSL 证书申请等常见 VPS 初始化任务，让新 VPS 快速投入使用。

### 核心功能

- **SSH 安全配置**: 自动修改 SSH 端口、配置公钥认证
- **Docker 环境**: 根据内存自动判断是否安装 Docker 和 Docker Compose
- **Web 服务器安装**: 在 Nginx 与 Caddy 中选择一个安装，或跳过安装
- **SSL 证书**: 集成 acme.sh 自动申请 Let's Encrypt 证书
- **BBR 优化**: 自动启用 TCP BBR 拥塞控制算法
- **系统优化**: 安装常用工具包、创建系统用户、配置环境
- **Node.js Agent CLI**: 可选安装 Codex CLI 与 Claude Code CLI

<!-- AUTO:tech-stack -->
## 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| 脚本语言 | POSIX Shell | - |
| 支持系统 | Debian/Ubuntu/Alpine | - |
| 容器化 | Docker | Latest |
| Web 服务器 | Nginx / Caddy | Latest |
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

# 3. 交互式初始化
chmod +x ./init.sh
./init.sh -i
```
<!-- /AUTO:quick-start -->

### 交互式初始化

在已连接终端的 VPS 上执行 `./init.sh -i` 会启动初始化向导。向导会依次配置时区、GitHub 镜像、SSH 加固、Let's Encrypt 邮箱，以及 MySQL 客户端、Docker、Web 服务器、Rclone、Glow、mise/Node.js、Codex CLI、Claude Code CLI、BBR 与 acme.sh。Web 服务器可选择 `nginx`、`caddy` 或 `none`，每次初始化最多安装一个。

只有选择安装 mise/Node.js LTS 后，向导才会分别询问是否安装 Codex CLI 和 Claude Code CLI；两项可以独立选择，默认均为安装。每个 CLI 随后可选输入 API Base URL；只有输入 Base URL 后才会要求输入隐藏的 token，且两者齐全时才会保存 API 配置。CLI 通过 mise 提供的 Node.js/npm 全局安装，npm registry 默认使用 npmmirror。

现有环境变量会显示为默认值，直接按 Enter 保留该值。向导不会额外生成交互配置文件；时区、SSH、镜像和软件安装等既有流程本来会修改的系统设置，仍会按确认结果执行。执行前会展示汇总，必须确认后才会开始修改系统。SSH 加固默认启用，包含公钥配置、禁用密码登录和将端口改为 `33022` 的选项。

### 无人值守初始化

`./init.sh` 不带参数时仍保持原有的无人值守行为，适用于云初始化和自动化脚本，默认选择 Nginx。`-h` 或 `--help` 可查看可用参数。

## 高级配置

### 自定义数据目录

脚本使用 `EZ_DATA` 作为宿主机数据目录。初始化脚本默认使用自身所在目录，独立模块默认使用仓库根目录；也可以显式覆盖：

```bash
EZ_DATA=/srv/vpsready ./init.sh
EZ_DATA=/srv/vpsready sh scripts/install/mysql.sh
```

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

### 选择 Web 服务器

使用 `WEB_SERVER` 预设 Web 服务器选择。可选值为 `nginx`、`caddy` 和 `none`；未设置时默认选择 Nginx。显式设置的值优先于低内存默认策略。检测到另一 Web 服务器或 80/443 端口监听时，脚本只会警告，不会停止、禁用或卸载已有服务。

```bash
WEB_SERVER=caddy ./init.sh
WEB_SERVER=none ./init.sh
```

### 自定义 Let's Encrypt 邮箱

```bash
LET_MAIL=your@email.com ./init.sh
```

### 使用 GitHub 镜像

```bash
MIRROR=https://ghmirror.pp.ua ./init.sh
```

### 使用 npm 镜像

Codex CLI 和 Claude Code CLI 默认从 npmmirror 的 npm registry（`https://registry.npmmirror.com`）安装。可通过 `NPM_REGISTRY` 覆盖为私有 registry 或 npm 官方源：

```bash
NPM_REGISTRY=https://registry.npmjs.org ./init.sh
NPM_REGISTRY=https://npm.example.com sh scripts/install/codex.sh
```

### 配置 Agent API

交互向导中可以分别配置 Codex 与 Claude Code 的 API endpoint。Base URL 留空时不会询问 token；token 留空时也不会保存配置。非交互模式可使用以下变量：

| CLI | Base URL | Token | 保存方式 |
|-----|----------|-------|----------|
| Codex | `CODEX_BASE_URL` | `CODEX_TOKEN` | 写入 `~/.codex/config.toml`，再通过 `codex login --with-api-key` 保存 token。 |
| Claude Code | `CLAUDE_BASE_URL` | `CLAUDE_TOKEN` | 写入仅当前用户可读的 `~/.config/vpsready/claude_code.env`，并由 `~/.profile` 与 `~/.bashrc` 加载。 |

```bash
CODEX_BASE_URL=https://api.example.com/v1 CODEX_TOKEN=your-token ./init.sh
CLAUDE_BASE_URL=https://claude.example.com CLAUDE_TOKEN=your-token ./init.sh
```

### 多参数组合

```bash
NOT_CHANGE_SSH_PORT=true LET_MAIL=your@email.com SSHKEY="ssh-rsa AAAA..." ./init.sh
```

### Docker CN 区域网络

CN 模式下使用 Docker CE 国内镜像源和 Docker Hub 加速器：

```bash
DOCKER_REGION=cn ./init.sh
```

`cn` 模式下，Debian/Ubuntu 从 Aliyun Docker CE 源安装，Alpine 从其已配置的 APK 源安装。Docker daemon 默认配置以下镜像加速器：

```text
https://docker.1ms.run
https://dockerproxy.net
https://proxy.vvvv.ee
https://dockerproxy.link
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_REGION` | `global` | `cn` 启用 CN 区域 Docker 安装和镜像配置；`global` 保持原行为。 |
| `DOCKER_INSTALL_MIRROR` | `Aliyun`（仅 `cn`） | Debian/Ubuntu Docker CE 源，可选 `Aliyun` 或 `AzureChinaCloud`。 |
| `DOCKER_INSTALLER_URL` | `https://get.docker.com` | `global` 模式使用的官方安装器地址。 |
| `DOCKER_REGISTRY_MIRROR` | CN 默认镜像列表（仅 `cn`） | 设置单个 `http://` 或 `https://` 地址覆盖默认列表；设置为 `none` 移除 `registry-mirrors`。 |

检测到命令行或可执行文件位于 `/usr/local/qcloud/` 的腾讯云代理进程时，脚本会自动使用腾讯云 Docker 镜像 `https://mirror.ccs.tencentyun.com`。显式设置 `DOCKER_REGISTRY_MIRROR`（包括 `none`）会覆盖此自动选择。

```bash
# 使用 Azure 中国 Docker CE 源
DOCKER_REGION=cn DOCKER_INSTALL_MIRROR=AzureChinaCloud ./init.sh

# 使用自建或指定的镜像加速器
DOCKER_REGION=cn DOCKER_REGISTRY_MIRROR=https://registry.example.com ./init.sh

# 仅使用 CN 区域 Docker CE 源，不写入镜像加速器
DOCKER_REGION=cn DOCKER_REGISTRY_MIRROR=none ./init.sh
```

`MIRROR` 仍只用于 GitHub 资源前缀；npm 包通过 `NPM_REGISTRY` 获取。若初始化脚本本身需要通过 GitHub 镜像获取，请单独设置 `MIRROR`。

### Docker 日志轮转配置

脚本会自动为 Docker 配置日志轮转策略，防止容器日志无限增长占用磁盘空间。

#### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_LOG_MAX_SIZE` | `10m` | 单个日志文件最大大小（如：`10m`, `50m`, `100m`） |
| `DOCKER_LOG_MAX_FILE` | `3` | 保留的日志文件数量（如：`3`, `5`, `10`） |
| `DOCKER_LOG_DRIVER` | `json-file` | 日志驱动类型 |
| `DOCKER_DISABLE_LOG_CONFIG` | `false` | 设为 `true` 跳过 daemon.json 日志与镜像配置 |

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
#   },
#   "registry-mirrors": [
#     "https://docker.1ms.run"
#   ]
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
sh -c "$(curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_logs.sh" -o -)"

# 或使用环境变量自定义配置
DOCKER_LOG_MAX_SIZE=50m DOCKER_LOG_MAX_FILE=5 sh -c "$(curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_logs.sh" -o -)"

# 配置 Docker CN Hub 镜像加速器
DOCKER_REGION=cn sh scripts/configure/docker_logs.sh
```

**环境变量：**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_LOG_MAX_SIZE` | `10m` | 单个日志文件最大大小 |
| `DOCKER_LOG_MAX_FILE` | `3` | 保留的日志文件数量 |
| `DOCKER_LOG_DRIVER` | `json-file` | 日志驱动类型 |
| `DOCKER_REGION` | `global` | 设置为 `cn` 时写入 CN 默认镜像加速器。 |
| `DOCKER_REGISTRY_MIRROR` | - | 单个自定义镜像地址；设为 `none` 移除镜像配置。 |

检测到腾讯云代理进程时，会自动使用腾讯云 Docker 镜像；`DOCKER_REGISTRY_MIRROR` 可覆盖此行为。

### 安装 SSH 公钥

```bash
bash -c "$(curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_key.sh" -o -)"
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
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_key.sh" | sh -s -- -k -P -A -M -S
```

如果脚本本身是通过 CDN 或镜像地址直接管道执行，公钥地址也要一并显式传入，因为 `curl | sh` 无法让脚本自动知道自己的来源 URL。例如 `jsdmirror`：

```bash
curl -fL "https://cdn.jsdmirror.com/gh/benzBrake/VPSReady@main/scripts/configure/ssh_key.sh" | sh -s -- -k -b "https://cdn.jsdmirror.com/gh/benzBrake/VPSReady@main"
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
| Caddy | `sh scripts/install/caddy.sh` | `MIRROR`、`GH_MIRROR`、`CADDY_*`、`DOWNLOAD_URL` |
| Docker | `sh scripts/install/docker.sh` | `DOCKER_REGION`、`DOCKER_INSTALL_MIRROR`、`DOCKER_REGISTRY_MIRROR`、`DOCKER_*` |
| MySQL | `sh scripts/install/mysql.sh` | `MYSQL_ROOT_PASSWORD`、`MYSQL_CONTAINER_NAME`、`MYSQL_IMAGE`、`MYSQL_DATA_DIR`、`MYSQL_PORT` |
| Glow | `sh scripts/install/glow.sh` | `GLOW_VERSION`、`GLOW_INSTALL_DIR`、`GLOW_MIRROR` |
| mise + Node.js LTS | `sh scripts/install/mise.sh` | `MISE_INSTALL_URL` |
| Codex CLI | `sh scripts/install/codex.sh` | `NPM_REGISTRY`、`CODEX_BASE_URL`、`CODEX_TOKEN`；默认 npmmirror；安装 `@openai/codex` |
| Claude Code CLI | `sh scripts/install/claude_code.sh` | `NPM_REGISTRY`、`CLAUDE_BASE_URL`、`CLAUDE_TOKEN`；默认 npmmirror；安装 `@anthropic-ai/claude-code` |
| tcping | `sh scripts/install/tcping.sh` | `GH_MIRROR`、`MIRROR`、`TCPING_VERSION`、`TCPING_INSTALL_DIR`、`TCPING_FORCE_REINSTALL` |
| Nginx | `sh scripts/install/nginx.sh` | 使用 `${EZ_DATA}/web` 配置 |

MySQL 模块要求 Docker 和 Docker Compose 均已可用；缺少 Docker 时会直接跳过。默认在 `${EZ_DATA}/mysql` 写入 `docker-compose.yml`、`.env` 和数据库数据目录，完成后会输出 root 密码。

远程完整命令：

```bash
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/acme.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/caddy.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/docker.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/mysql.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/glow.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/mise.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/codex.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/claude_code.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/nginx.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/install/tcping.sh" | sh
```

mise 会默认安装最新 LTS 版本的 Node.js，并将其设为全局版本，也可以使用 `mise run <task>` 执行项目任务。可使用以下命令切换 Node.js 版本：

```bash
# 设置全局版本
mise use --global node@20

# 设置当前项目版本
mise use node@20

# 临时切换当前 shell 的版本
mise shell node@20
```

安装 Agent CLI（需先完成 mise 与 Node.js LTS 安装）：

```bash
sh scripts/install/codex.sh
sh scripts/install/claude_code.sh
```

旧版 `nvm.sh` 仍保留用于兼容，但 `init.sh` 不再自动调用 NVM。

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

远程完整命令：

```bash
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_iptables.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/docker_logs.sh" | sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_key.sh" | sh -s -- -k
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/configure/ssh_port.sh" | sh
```

#### 工具模块

以下命令均可直接复制。将路径、实例名或 token 文件路径替换为自己的值。

```bash
# 备份 EZ_DATA，并保留默认配置
sudo sh scripts/tools/backup.sh

# 安装 cloudflared（未安装时）并显示版本
sudo sh scripts/tools/cloudflared.sh --version

# 创建名为 blog 的 Cloudflare Tunnel 实例
sudo sh scripts/tools/cloudflare_tunnel.sh add blog

# 从文件读取 token 创建名为 api 的 Tunnel 实例
sudo sh scripts/tools/cloudflare_tunnel.sh add api --token-file /root/api-tunnel-token

# 查找 EZ_DATA 下大于 500 MB 的文件
sh scripts/tools/find_large_files.sh "${EZ_DATA:-$(pwd)}" 500
```

远程完整命令：

```bash
# 下载到临时文件后执行，避免远程脚本依赖相对路径时失效
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/tools/backup.sh" -o /tmp/vpsready-backup.sh && sudo bash /tmp/vpsready-backup.sh
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/tools/cloudflared.sh" -o /tmp/vpsready-cloudflared.sh && sudo sh /tmp/vpsready-cloudflared.sh --version
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/tools/cloudflare_tunnel.sh" -o /tmp/vpsready-cloudflare-tunnel.sh && sudo sh /tmp/vpsready-cloudflare-tunnel.sh add blog
curl -fL "https://raw.githubusercontent.com/benzBrake/VPSReady/main/scripts/tools/find_large_files.sh" -o /tmp/vpsready-find-large-files.sh && sh /tmp/vpsready-find-large-files.sh "${EZ_DATA:-$(pwd)}" 500
```

`backup.sh` 需要先通过环境变量或编辑脚本配置备份目录、数据库和远端存储；其默认的 MySQL 密码占位值不可直接用于生产环境。

`.ezenv` 是部署到 `${EZ_DATA}/.ezenv` 的运行时环境文件，会将 `${EZ_DATA}/scripts/tools` 加入 `PATH`，并加载 `${EZ_DATA}/.ez/ez.bash`。加载前必须设置 `EZ_DATA`，不要把它当作可执行模块运行。

### Cloudflare Tunnel 多实例管理

`scripts/tools/cloudflare_tunnel.sh` 使用 Cloudflare Zero Trust 控制台生成的 tunnel token，管理多个相互独立的本机连接器。无参数运行时进入交互菜单，也可以使用子命令自动化操作：

```bash
# 进入交互菜单
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh

# 安全地交互输入 token 或粘贴 Cloudflare service install 命令
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh add blog

# 从文件读取 token，token 不会出现在进程参数中
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh add api --token-file /root/api-tunnel-token

# 查看并管理实例
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh list
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh status blog
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh stop blog
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh start blog
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh restart blog

# 删除本机实例，需要确认；自动化脚本可以使用 --force
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh remove blog
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh remove api --force

# 创建退出后即失效的 Quick Tunnel
${EZ_DATA:-$(pwd)}/scripts/tools/cloudflare_tunnel.sh temp http://127.0.0.1:8080
```

交互输入支持直接粘贴纯 token，也支持 Cloudflare 控制台提供的 `cloudflared service install <token>`、`cloudflared.exe service install <token>` 及带 `sudo` 的形式。脚本只从严格匹配的命令中提取 token，不会执行粘贴的命令；`--token-file` 指定的文件仍应只包含纯 token。

如果系统安装了 Docker，脚本会为每条 tunnel 创建一个使用 `unless-stopped` 重启策略的独立容器。Docker 已安装但 daemon 不可用时，脚本会报错，不会混用原生模式。如果没有安装 Docker，Debian/Ubuntu 使用 systemd，Alpine 使用 OpenRC，并配置开机启动。

实例数据默认保存在 `${EZ_DATA}/cloudflared/tunnels/<name>`。token 文件权限为 `600`，Docker 容器和系统服务均通过 token 文件启动，不把 token 写入命令参数。实例名称只允许小写字母、数字、下划线和连字符。

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
MIRROR=https://ghmirror.pp.ua bash <(curl -fL https://ghmirror.pp.ua/https://github.com/benzBrake/warp.sh/raw/main/warp.sh) 4
```

## 安全注意事项

⚠️ **克隆后务必更换 `pub/` 目录下的公钥**

## 许可证

本项目采用开源许可证，详见 [LICENSE](./LICENSE) 文件。
