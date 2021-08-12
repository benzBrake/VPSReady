#!/bin/sh
if [ ! -f /data/web/nginx-frontend.conf ]; then
  cp /data/web/demo-config/web.conf /data/web/nginx-frontend.conf
  CORES=$(cat /proc/cpuinfo | grep processor | wc -l)
  sed -i "s/worker_processes.*/worker_processes  ${CORES}/" /data/web/nginx-frontend.conf
fi