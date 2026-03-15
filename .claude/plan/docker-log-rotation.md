# Docker 日志轮转自动化配置规划文档

> 规划日期: 2026-03-15
> 项目: VPSReady
> 目标文件: `.init/docker.sh`

---

## 1. 目标定义

### 1.1 功能目标

为核心脚本 `.init/docker.sh` 增加以下能力：

1. **全局日志轮转配置**: 在 Docker 安装后自动配置 daemon.json，使所有容器默认启用日志轮转
2. **环境变量驱动**: 支持通过环境变量自定义日志配置参数
3. **配置智能合并**: 检测并合并现有 daemon.json 配置，避免覆盖用户自定义配置
4. **POSIX 兼容**: 仅使用 POSIX sh 标准语法，确保在 Debian/Ubuntu/Alpine 上的兼容性
5. **可回滚性**: 配置失败时能够恢复原有状态

### 1.2 验收标准

- [ ] 在无 daemon.json 时创建新配置文件
- [ ] 在已有 daemon.json 时正确合并日志配置
- [ ] 支持通过环境变量覆盖默认值
- [ ] Docker 服务重启后配置生效
- [ ] 配置失败时能够恢复并报错
- [ ] 在 Debian/Ubuntu/Alpine 上测试通过
- [ ] 不影响现有 Docker 安装流程

---

## 2. 技术方案

### 2.1 Docker daemon.json 配置方案

**目标配置结构** (`/etc/docker/daemon.json`):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

**配置说明**:
- `log-driver`: 使用 json-file 驱动（Docker 默认）
- `max-size`: 单个日志文件最大大小（默认 10m）
- `max-file`: 保留的日志文件数量（默认 3 个）

### 2.2 环境变量设计

| 环境变量 | 默认值 | 说明 | 示例 |
|---------|--------|------|------|
| `DOCKER_LOG_MAX_SIZE` | `10m` | 单个日志文件最大大小 | `10m`, `50m`, `100m` |
| `DOCKER_LOG_MAX_FILE` | `3` | 保留的日志文件数量 | `3`, `5`, `10` |
| `DOCKER_LOG_DRIVER` | `json-file` | 日志驱动类型 | `json-file`, `journald` |
| `DOCKER_DISABLE_LOG_CONFIG` | `false` | 禁用日志配置 | `true` 跳过配置 |

### 2.3 POSIX JSON 操作策略

由于 POSIX sh 缺乏原生 JSON 支持，采用以下策略：

**方案选择: sed 行操作 + 模板替换**

```sh
# 1. 检测文件是否存在
# 2. 不存在：直接写入完整配置
# 3. 存在：使用 sed 进行智能合并
#    - 检测并更新 "log-driver" 行
#    - 检测并更新/添加 "log-opts" 部分
```

**技术优势**:
- 不依赖 jq/awk 高级特性
- 兼容所有 POSIX 系统
- 代码简洁易维护
- 误操作风险低

---

## 3. 实施步骤

### 3.1 配置文件检测与创建逻辑

```sh
# 步骤流程
1. 检查 DOCKER_DISABLE_LOG_CONFIG 环境变量
2. 检测 Docker 是否已安装 (docker --version)
3. 确定 daemon.json 路径:
   - 默认: /etc/docker/daemon.json
   - 检测目录存在性，不存在则创建
4. 备份现有配置 (如果存在)
```

### 3.2 JSON 配置合并策略

#### 3.2.1 文件不存在场景

```sh
# 直接写入完整配置
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "${DOCKER_LOG_DRIVER:-json-file}",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE:-10m}",
    "max-file": "${DOCKER_LOG_MAX_FILE:-3}"
  }
}
EOF
```

#### 3.2.2 文件存在场景

使用三阶段处理策略：

**阶段 1: log-driver 配置**
```sh
# 检测是否存在 "log-driver" 行
if grep -q '"log-driver"' /etc/docker/daemon.json; then
    # 更新现有配置
    sed -i 's/"log-driver":\s*"[^"]*"/"log-driver": "json-file"/' \
        /etc/docker/daemon.json
else
    # 添加新配置（在最后一个 } 前添加）
    sed -i 's/}$/,\n  "log-driver": "json-file"\n}/' \
        /etc/docker/daemon.json
fi
```

**阶段 2: log-opts 配置**
```sh
# 检测是否存在 "log-opts" 对象
if grep -q '"log-opts"' /etc/docker/daemon.json; then
    # 更新现有 log-opts 中的 max-size
    if grep -q '"max-size"' /etc/docker/daemon.json; then
        sed -i 's/"max-size":\s*"[^"]*"/"max-size": "10m"/' \
            /etc/docker/daemon.json
    else
        # 在 log-opts 对象中添加 max-size
        sed -i '/"log-opts":\s*{/a\    "max-size": "10m",' \
            /etc/docker/daemon.json
    fi

    # 同理处理 max-file
    # ...
else
    # 添加完整的 log-opts 对象
    sed -i 's/}$/,\n  "log-opts": {\n    "max-size": "10m",\n    "max-file": "3"\n  }\n}/' \
        /etc/docker/daemon.json
fi
```

**阶段 3: JSON 语法验证**
```sh
# 使用 Python 或其他 JSON 验证工具（如果可用）
# 或简单的括号匹配检查
```

### 3.3 Docker 服务重启流程

```sh
# 1. 验证配置文件语法
# 2. 重启 Docker 服务
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart docker
elif command -v service >/dev/null 2>&1; then
    service docker restart
else
    # Alpine 或其他系统
    /etc/init.d/docker restart
fi

# 3. 验证服务状态
if ! docker info >/dev/null 2>&1; then
    err "Docker failed to start after configuration"
    # 执行回滚
fi
```

### 3.4 错误处理与回滚

**回滚策略**:

```sh
# 1. 配置前备份
if [ -f /etc/docker/daemon.json ]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
fi

# 2. 配置失败时恢复
rollback_daemon_config() {
    if [ -f /etc/docker/daemon.json.bak ]; then
        warn "Restoring daemon.json from backup"
        mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
        # 重启 Docker 使恢复生效
        restart_docker_service
    fi
}

# 3. 调用回滚
if ! configure_docker_logs; then
    err "Failed to configure Docker logs"
    rollback_daemon_config
    exit 1
fi
```

**错误场景处理**:

| 错误场景 | 处理方法 | 用户提示 |
|---------|---------|---------|
| 配置目录不可写 | 跳过配置，记录警告 | `[W] Cannot write to /etc/docker/` |
| JSON 语法错误 | 回滚配置，报错退出 | `[E] Invalid JSON syntax, rolling back` |
| Docker 重启失败 | 回滚配置，保持原状 | `[E] Docker failed to start, restored config` |
| sed 操作失败 | 回滚配置，报错退出 | `[E] Failed to update daemon.json` |

---

## 4. 测试验证

### 4.1 不同系统测试场景

#### 测试矩阵

| 系统 | Docker 版本 | daemon.json 初始状态 | 测试点 |
|-----|------------|---------------------|-------|
| Ubuntu 20.04 | Latest | 不存在 | 创建新配置 |
| Ubuntu 22.04 | 20.10 | 存在（无日志配置） | 添加日志配置 |
| Debian 11 | 23.0 | 存在（有日志配置） | 更新日志配置 |
| Alpine 3.18 | Latest | 不存在 | 创建配置（无 systemd） |
| Alpine 3.19 | 24.0 | 存在（复杂配置） | 合并复杂配置 |

#### 测试用例

**测试用例 1: 全新安装**
```sh
# 前置条件
- 无 /etc/docker/daemon.json

# 预期结果
- 创建 /etc/docker/daemon.json
- 包含正确的 log-driver 和 log-opts
- Docker 服务正常运行
```

**测试用例 2: 已有简单配置**
```sh
# 前置条件
- /etc/docker/daemon.json 存在
- 内容: {"registry-mirrors": ["https://mirror.gcr.io"]}

# 预期结果
- 保留 registry-mirrors 配置
- 添加 log-driver 和 log-opts
- 最终 JSON 语法正确
```

**测试用例 3: 已有日志配置**
```sh
# 前置条件
- /etc/docker/daemon.json 包含 log-opts
- max-size: "50m", max-file: "5"

# 预期结果
- 更新为新的默认值（10m, 3）
- 或保留原值（根据设计选择）
```

**测试用例 4: 环境变量覆盖**
```sh
# 前置条件
- DOCKER_LOG_MAX_SIZE=100m
- DOCKER_LOG_MAX_FILE=10

# 预期结果
- 配置文件中使用 100m 和 10
```

### 4.2 配置验证方法

#### 方法 1: Docker 信息检查
```sh
# 检查全局配置
docker info | grep -A 5 "Logging Driver"

# 预期输出
# Logging Driver: json-file
```

#### 方法 2: 容器日志测试
```sh
# 启动测试容器
docker run -d --name log-test nginx:alpine

# 生成日志
for i in $(seq 1 100); do
    docker exec log-test sh -c "echo test log $i"
done

# 检查日志文件
ls -lh /var/lib/docker/containers/<container-id>/*-json.log

# 预期结果
# 日志文件大小不超过 max-size 配置
# 日志文件数量不超过 max-file 配置
```

#### 方法 3: 配置文件验证
```sh
# 验证 JSON 语法
python3 -m json.tool /etc/docker/daemon.json

# 或使用 jq（如果已安装）
jq . /etc/docker/daemon.json
```

### 4.3 回滚测试

**回滚测试用例**:
```sh
# 1. 模拟配置失败场景
#    - 人为制造无效 JSON
#    - 测试回滚逻辑

# 2. 验证回滚后状态
#    - daemon.json 恢复原状
#    - Docker 服务正常运行
#    - 日志输出清晰提示
```

---

## 5. 风险与缓解

### 5.1 潜在问题

| 风险 | 影响 | 概率 | 缓解策略 |
|-----|------|------|---------|
| **sed 操作破坏 JSON 结构** | Docker 无法启动 | 中 | 1. 操作前备份<br>2. 使用保守的 sed 模式<br>3. 操作后验证 JSON 语法 |
| **权限不足** | 配置写入失败 | 低 | 1. 脚本以 root 运行（项目已有保证）<br>2. 检测目录可写性<br>3. 友好错误提示 |
| **系统差异** | 某些系统不支持 | 低 | 1. 严格遵循 POSIX sh<br>2. 使用命令存在性检测<br>3. 提供多分支兼容逻辑 |
| **现有配置冲突** | 覆盖用户自定义配置 | 中 | 1. 智能合并而非覆盖<br>2. 详细日志输出操作内容<br>3. 提供禁用开关 |
| **Docker 服务重启失败** | 服务不可用 | 中 | 1. 重启前验证配置语法<br>2. 失败时自动回滚<br>3. 提供手动恢复指引 |

### 5.2 设计决策权衡

#### 决策 1: JSON 操作方式

**选项 A: 使用 jq**
- 优点: 简洁可靠
- 缺点: 需要额外依赖

**选项 B: 使用 sed + grep（选择）**
- 优点: 无额外依赖，POSIX 兼容
- 缺点: 实现复杂，边界情况多

**选择理由**: 项目强调无依赖和 POSIX 兼容性

#### 决策 2: 配置合并策略

**选项 A: 覆盖式**
- 优点: 实现简单
- 缺点: 破坏现有配置

**选项 B: 合并式（选择）**
- 优点: 保留用户配置
- 缺点: 实现复杂

**选择理由**: 保护用户现有配置，降低风险

#### 决策 3: 错误处理策略

**选项 A: 失败即停止**
- 优点: 避免累积错误
- 缺点: 可能中断安装流程

**选项 B: 失败跳过（选择）**
- 优点: 不影响主流程
- 缺点: 日志配置可能缺失

**选择理由**: 日志配置是增强功能，不应阻止 Docker 安装

---

## 6. 实施计划

### 6.1 开发阶段

**阶段 1: 核心功能实现** (预计 2-3 小时)
- [ ] 编写配置文件检测逻辑
- [ ] 实现 daemon.json 创建
- [ ] 实现配置合并逻辑
- [ ] 添加错误处理和回滚

**阶段 2: 集成与测试** (预计 1-2 小时)
- [ ] 集成到 docker.sh
- [ ] 本地测试各种场景
- [ ] 修复边界问题

**阶段 3: 文档与优化** (预计 1 小时)
- [ ] 更新 README.md
- [ ] 添加环境变量说明
- [ ] 代码优化和注释

### 6.2 代码结构建议

```sh
# .init/docker.sh 新结构

#!/bin/sh

# === 环境变量与配置 ===
DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE:-10m}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE:-3}
DOCKER_LOG_DRIVER=${DOCKER_LOG_DRIVER:-json-file}

# === 工具函数 ===
info() { echo "[I] $*"; }
warn() { echo "[W] $*"; }
err() { echo "[E] $*"; }
suc() { echo "[S] $*"; }

# === 核心函数 ===
configure_docker_logs() {
    # 1. 检查禁用标志
    # 2. 检测 daemon.json
    # 3. 备份配置
    # 4. 合并/创建配置
    # 5. 验证配置
    # 6. 重启服务
}

backup_daemon_config() { ... }
merge_log_config() { ... }
validate_json() { ... }
restart_docker() { ... }
rollback_config() { ... }

# === 主流程 ===
# 原有的 Docker 安装逻辑
bash -c "$(curl -fsSL https://get.docker.com -o -)"
apt-get update
apt-get -y install docker-compose

# 新增日志配置
if [ "${DOCKER_DISABLE_LOG_CONFIG}" != "true" ]; then
    info "Configuring Docker log rotation..."
    configure_docker_logs
fi
```

### 6.3 关键注意事项

1. **保持向后兼容**: 不破坏现有 docker.sh 的功能
2. **日志输出规范**: 使用项目的 info/warn/err/suc 函数
3. **错误不中断**: 日志配置失败不应阻止 Docker 安装
4. **代码风格一致**: 遵循现有代码的缩进和命名规范
5. **POSIX 严格性**: 避免使用 bash 特性（如数组、[[ ]]）

---

## 7. 验收检查清单

### 7.1 功能验收

- [ ] 在全新系统上正确创建 daemon.json
- [ ] 在已有配置时正确合并
- [ ] 环境变量能够覆盖默认值
- [ ] DOCKER_DISABLE_LOG_CONFIG=true 跳过配置
- [ ] Docker 服务重启后配置生效
- [ ] 新容器自动应用日志轮转
- [ ] 配置失败时正确回滚

### 7.2 系统兼容性

- [ ] Ubuntu 18.04+ 测试通过
- [ ] Debian 10+ 测试通过
- [ ] Alpine 3.x 测试通过
- [ ] WSL 环境正确跳过（遵循项目现有逻辑）

### 7.3 代码质量

- [ ] 仅使用 POSIX sh 语法
- [ ] 函数命名清晰，注释充分
- [ ] 错误处理完善
- [ ] 日志输出友好
- [ ] 代码风格与项目一致

### 7.4 文档完整性

- [ ] README.md 更新环境变量说明
- [ ] 添加配置示例
- [ ] 说明故障排查方法

---

## 8. 后续优化方向

1. **日志驱动扩展**: 支持更多日志驱动（journald, syslog 等）
2. **配置验证增强**: 集成 JSON schema 验证
3. **日志分析工具**: 提供日志使用情况分析脚本
4. **监控集成**: 与现有监控系统集成日志告警

---

### Critical Files for Implementation

基于项目结构分析，实施此规划最关键的文件：

- **E:\WorkSpace\Bash\VPSReady\.init\docker.sh** - 核心目标文件，需实现日志配置逻辑（当前仅 3 行，需扩展到 150-200 行）
- **E:\WorkSpace\Bash\VPSReady\.utils\common.sh** - 通用函数库，可能需要新增日志配置相关工具函数（当前仅 17 行，提供基础日志函数）
- **E:\WorkSpace\Bash\VPSReady\README.md** - 需更新环境变量配置说明，添加 DOCKER_LOG_* 系列变量文档
- **E:\WorkSpace\Bash\VPSReady\init.sh** - 主初始化脚本，验证集成逻辑和调用流程（当前 203 行，处理 Docker 安装决策）
- **E:\WorkSpace\Bash\VPSReady\.init\ssh_port.sh** - 配置文件修改参考模式（57 行，展示了配置备份、修改、服务重启、回滚的完整流程）
