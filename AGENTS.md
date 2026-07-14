# VPSReady 项目配置

## 项目概述
VPS 自动化初始化脚本项目，用于快速配置新 VPS 环境。

## 技术栈
- **语言**: Shell (POSIX sh)
- **支持系统**: Debian/Ubuntu/Alpine
- **工具**: Docker, Nginx, acme.sh, Rclone

## 项目结构
```
VPSReady/
├── scripts/            # 可单独执行的脚本（install/configure/tools）
│   ├── acme.sh        # ACME SSL 证书安装
│   ├── caddy.sh       # Caddy 安装
│   ├── docker.sh      # Docker 安装
│   ├── docker_iptables.sh # Docker 端口白名单配置
│   ├── docker_logs.sh # Docker 日志轮转配置
│   ├── glow.sh        # Glow 安装
│   ├── nginx.sh       # Nginx 安装
│   ├── ssh_key.sh     # SSH 公钥配置
│   └── ssh_port.sh    # SSH 端口修改
├── lib/                # Shell 函数库
│   ├── backup.sh      # 备份工具
│   ├── cloudflared.sh # Cloudflared 工具
│   ├── common.sh      # 通用函数（已迁移至 lib/）
│   └── find_large_files.sh # 大文件查找工具
├── Dockerfiles/        # Docker 配置文件
├── web/                # Web 配置示例
├── pub/                # 公钥目录（需用户自行替换）
├── init.sh             # 主初始化脚本入口
├── .ezenv              # 环境变量配置
└── .docker-compose.yml.demo  # Docker Compose 示例
```

## 开发规范

### Shell 脚本规范
- 遵循 POSIX sh 标准，避免使用 bash 特性
- 使用 `#!/usr/bin/env sh` 作为 shebang
- 变量使用大写字母：`MY_VAR="value"`
- 函数名使用小写加下划线：`my_function()`
- 字符串变量引用必须加双引号：`"${MY_VAR}"`
- 使用 `[ ]` 进行测试，避免使用 `[[ ]]`
- 错误处理：关键命令后检查 `$?`

### Alpine 下载兼容性
- Alpine 的最小镜像默认只提供 BusyBox `wget`，不能假设已安装 `curl`。
- 任何需要下载远程内容的脚本都必须优先检测可用下载工具，并在 `curl` 不存在时兼容 BusyBox `wget`；除非脚本明确先安装了 `curl`。
- 使用 `wget` 时采用 BusyBox 兼容参数，例如 `wget -qO "${OUTPUT_FILE}" "${URL}"`，避免 GNU Wget 专有选项。

### 代码风格
- 缩进使用 4 空格
- 函数定义与调用之间空一行
- 注释使用 `#`，重要逻辑必须添加注释
- 长命令使用 `\` 续行

### Shell 文件命名
- 文件名统一使用小写 `snake_case`，不使用连字符
- 目录负责表达脚本类别，文件名优先描述操作对象
- 需要区分操作时使用“动作 + 对象”，例如 `find_large_files.sh`

### 安全规范
- 所有变量引用必须使用 `${VAR}` 形式
- 用户输入必须验证
- 敏感信息（密码、密钥）不硬编码
- 使用 `set -e` 在关键脚本中启用错误退出

## 测试
在以下环境测试脚本：
- Debian 11/12
- Ubuntu 20.04/22.04
- Alpine 3.x

## Git 工作流

### .sh 文件权限管理
**重要**：所有 .sh 脚本文件必须具有可执行权限（100755）。

项目使用 `.githooks/pre-commit` hook 自动管理权限，提交时自动为新增或修改的 .sh 文件设置 `+x`。

**克隆后首次配置**：
```bash
git config core.hooksPath .githooks
```

**手动修复权限**：
```bash
git update-index --chmod=+x path/to/script.sh
```

### 提交规范
- feat: 新功能
- fix: 修复
- docs: 文档更新
- refactor: 重构
