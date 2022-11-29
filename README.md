# VPSReady
VPS初始化脚本
因为 CentOS 被切换到 Stream，估计以后写SHELL都不考虑RHEL系了。

ℹ克隆脚本以后记得更换pub目录下的公钥

## 安装脚本

```
apt-get update && apt-get -y install git
git clone https://github.com/benzBrake/VPSReady /data
```
## 使用
### 初始化 VPS
```
bash init.sh
```