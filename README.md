<!--
 * @Author: Ryan
 * @Date: 2021-02-22 20:17:25
 * @LastEditTime: 2021-02-23 15:50:07
 * @LastEditors: Ryan
 * @Description: 
 * @FilePath: \VPSReady\README.md
-->
# VPSReady
VPS初始化脚本
因为 CentOS 被切换到 Stream，估计以后写SHELL都不考虑RHEL系了。
## 安装脚本
```
apt-get udpate && apt-get -y install git
git clone https://github.com/benzBrake/VPSReady /data
```
## 使用
### 初始化 VPS
```
bash init.sh
```