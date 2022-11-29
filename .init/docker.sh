#!/bin/sh
bash -c "$(curl -fsSL https://get.docker.com -o -)"
apt-get update
apt-get -y install docker-compose