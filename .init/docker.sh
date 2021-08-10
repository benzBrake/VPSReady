#!/bin/sh
bash -c "$(curl -fsSL https://get.docker.com -o -)"
apt-get update
apt-get install docker-compose
