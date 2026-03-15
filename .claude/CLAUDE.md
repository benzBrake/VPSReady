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
├── .init/              # 初始化模块脚本
│   ├── acme.sh        # ACME SSL 证书安装
│   ├── docker.sh      # Docker 安装
│   ├── nginx.sh       # Nginx 安装
│   ├── ssh_key.sh     # SSH 公钥配置
│   └── ssh_port.sh    # SSH 端口修改
├── .utils/             # 工具函数库
│   ├── backup.sh      # 备份工具
│   └── common.sh      # 通用函数
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

### 代码风格
- 缩进使用 4 空格
- 函数定义与调用之间空一行
- 注释使用 `#`，重要逻辑必须添加注释
- 长命令使用 `\` 续行

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

## 提交规范
- feat: 新功能
- fix: 修复
- docs: 文档更新
- refactor: 重构
