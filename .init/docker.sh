#!/bin/sh
###
 # @Author: Ryan
 # @Date: 2021-02-22 20:48:42
 # @LastEditTime: 2021-02-22 20:49:21
 # @LastEditors: Ryan
 # @Description: 
 # @FilePath: \VPSReady\docker.sh
### 
bash -c "$(curl -fsSL https://get.docker.com -o -)"
apt-get update
apt-get install docker-compose
