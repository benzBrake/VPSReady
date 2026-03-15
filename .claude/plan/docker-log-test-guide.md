# Docker 日志轮转配置测试指南

本文档提供 Docker 日志轮转功能的完整测试指南。

## 测试环境要求

- **操作系统**: Debian 9+, Ubuntu 18.04+, Alpine 3.x
- **权限**: root 用户
- **网络**: 可访问 Docker 官方安装脚本

## 测试场景

### 场景 1: 全新安装（无 daemon.json）

**前置条件**:
- 系统未安装 Docker
- 无 `/etc/docker/daemon.json` 文件

**测试步骤**:

```bash
# 1. 确保环境干净
sudo rm -rf /etc/docker
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# 2. 运行脚本（使用默认配置）
sudo bash .init/docker.sh

# 3. 验证结果
cat /etc/docker/daemon.json
```

**预期结果**:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

**验证 Docker 服务**:
```bash
sudo systemctl status docker
docker info | grep -A 5 "Logging Driver"
```

---

### 场景 2: 已有简单配置

**前置条件**:
- Docker 已安装
- `/etc/docker/daemon.json` 存在且包含简单配置

**测试步骤**:

```bash
# 1. 创建现有配置
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}
EOF

# 2. 运行脚本
sudo bash .init/docker.sh

# 3. 验证结果
cat /etc/docker/daemon.json
```

**预期结果**:
```json
{
  "registry-mirrors": ["https://mirror.gcr.io"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

**验证点**:
- 原有的 `registry-mirrors` 配置被保留
- 日志配置被正确添加
- JSON 语法正确

---

### 场景 3: 已有日志配置（更新）

**前置条件**:
- `/etc/docker/daemon.json` 包含旧的日志配置

**测试步骤**:

```bash
# 1. 创建包含日志配置的文件
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
EOF

# 2. 运行脚本
sudo bash .init/docker.sh

# 3. 验证结果
cat /etc/docker/daemon.json
```

**预期结果**:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

**验证点**:
- 旧的日志配置被更新为新的默认值

---

### 场景 4: 环境变量覆盖

**测试步骤**:

```bash
# 1. 删除现有配置
sudo rm -f /etc/docker/daemon.json

# 2. 使用自定义环境变量
sudo DOCKER_LOG_MAX_SIZE=100m DOCKER_LOG_MAX_FILE=10 bash .init/docker.sh

# 3. 验证结果
cat /etc/docker/daemon.json
```

**预期结果**:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "10"
  }
}
```

---

### 场景 5: 禁用日志配置

**测试步骤**:

```bash
# 1. 删除现有配置
sudo rm -f /etc/docker/daemon.json

# 2. 使用环境变量禁用
sudo DOCKER_DISABLE_LOG_CONFIG=true bash .init/docker.sh

# 3. 验证结果
ls -la /etc/docker/daemon.json
```

**预期结果**:
- `daemon.json` 文件不存在（或保持原状）
- Docker 服务正常运行

---

### 场景 6: 配置失败回滚

**测试步骤**:

```bash
# 1. 创建有效配置作为备份源
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}
EOF

# 2. 手动模拟配置失败场景（修改脚本制造错误）
# 在 merge_log_config 函数中故意返回错误

# 3. 运行脚本并观察回滚
sudo bash .init/docker.sh

# 4. 验证配置被恢复
cat /etc/docker/daemon.json
```

**预期结果**:
- 配置被恢复到原始状态
- 错误信息清晰显示

---

## 容器日志测试

### 测试日志轮转功能

```bash
# 1. 启动一个会生成日志的容器
docker run -d --name log-test nginx:alpine

# 2. 生成大量日志
for i in $(seq 1 100); do
    docker exec log-test sh -c "echo 'Test log entry $i' >&2"
done

# 3. 查看容器日志文件
CONTAINER_ID=$(docker inspect -f '{{.Id}}' log-test)
ls -lh /var/lib/docker/containers/${CONTAINER_ID}/*-json.log

# 4. 验证日志文件大小
# 日志文件应该接近配置的 max-size (10m)
# 旧日志文件被轮转，保留 max-file 数量的文件
```

---

## 系统兼容性测试

### Ubuntu 20.04

```bash
# 测试 systemctl 支持
sudo bash .init/docker.sh
systemctl status docker
```

### Alpine 3.18+

```bash
# 测试 init.d 支持
sudo bash .init/docker.sh
/etc/init.d/docker status
```

---

## 验证检查清单

### 功能验收

- [ ] 全新安装正确创建 daemon.json
- [ ] 已有配置时正确合并
- [ ] 环境变量能够覆盖默认值
- [ ] DOCKER_DISABLE_LOG_CONFIG=true 跳过配置
- [ ] Docker 服务重启后配置生效
- [ ] 新容器自动应用日志轮转
- [ ] 配置失败时正确回滚

### 系统兼容性

- [ ] Ubuntu 18.04+ 测试通过
- [ ] Debian 10+ 测试通过
- [ ] Alpine 3.x 测试通过

### 代码质量

- [ ] 仅使用 POSIX sh 语法
- [ ] 函数命名清晰，注释充分
- [ ] 错误处理完善
- [ ] 日志输出友好

---

## 故障排查

### Docker 服务启动失败

```bash
# 检查配置文件语法
python3 -m json.tool /etc/docker/daemon.json

# 查看 Docker 日志
sudo journalctl -u docker -n 50

# 恢复备份
sudo mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
sudo systemctl restart docker
```

### 日志配置未生效

```bash
# 验证配置
docker info | grep -A 5 "Logging Driver"

# 检查容器日志配置
docker inspect <container-id> | grep -A 10 "LogConfig"

# 手动指定日志配置运行容器
docker run --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 nginx
```

---

## 性能影响评估

### 日志轮转开销

- **CPU**: minimal（仅在日志文件达到大限时触发）
- **磁盘**: 不会超过 `max-size × max-file`
- **I/O**: 轮转时短暂增加，可忽略

### 推荐配置

| 场景 | max-size | max-file |
|------|----------|----------|
| 开发测试 | 10m | 3 |
| 生产环境 | 50m | 5 |
| 高负载应用 | 100m | 10 |

---

## 自动化测试脚本

```bash
#!/bin/sh
# Docker 日志配置自动化测试脚本

echo "=== Docker Log Configuration Test Suite ==="

# 测试 1: 语法检查
echo "[Test 1] Script syntax check..."
if sh -n .init/docker.sh; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax error found"
    exit 1
fi

# 测试 2: 函数存在性检查
echo "[Test 2] Function existence check..."
for func in configure_docker_logs backup_daemon_config create_daemon_config \
            merge_log_config validate_json_syntax restart_docker_service \
            verify_docker_service rollback_daemon_config; do
    if grep -q "^${func}()" .init/docker.sh; then
        echo "✓ Function ${func} found"
    else
        echo "✗ Function ${func} not found"
        exit 1
    fi
done

# 测试 3: 环境变量默认值
echo "[Test 3] Environment variable defaults..."
source .init/docker.sh
if [ "${DOCKER_LOG_MAX_SIZE}" = "10m" ] && \
   [ "${DOCKER_LOG_MAX_FILE}" = "3" ] && \
   [ "${DOCKER_LOG_DRIVER}" = "json-file" ]; then
    echo "✓ Default values correct"
else
    echo "✗ Default values incorrect"
    exit 1
fi

echo ""
echo "=== All automated tests passed ==="
echo "Note: Full integration testing requires root privileges and actual Docker installation."
```

---

## 测试报告模板

```markdown
# Docker 日志配置测试报告

**测试日期**: YYYY-MM-DD
**测试环境**: [Ubuntu 20.04 / Debian 11 / Alpine 3.18]
**测试人员**: [Name]

## 测试结果摘要

| 测试场景 | 结果 | 备注 |
|---------|------|------|
| 场景 1: 全新安装 | ✓ / ✗ | |
| 场景 2: 简单配置合并 | ✓ / ✗ | |
| 场景 3: 日志配置更新 | ✓ / ✗ | |
| 场景 4: 环境变量覆盖 | ✓ / ✗ | |
| 场景 5: 禁用配置 | ✓ / ✗ | |
| 场景 6: 配置失败回滚 | ✓ / ✗ | |

## 问题描述

[记录测试中发现的问题]

## 建议改进

[记录改进建议]
```
