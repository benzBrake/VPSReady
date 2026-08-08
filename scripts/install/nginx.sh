#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
EZ_DATA="${EZ_DATA:-$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)}"
if [ ! -f "${EZ_DATA}/web/nginx-frontend.conf" ]; then
  cp "${EZ_DATA}/web/demo-config/web.conf" "${EZ_DATA}/web/nginx-frontend.conf"
  CORES=$(cat /proc/cpuinfo | grep processor | wc -l)
  sed -i "s/worker_processes.*/worker_processes  ${CORES};/" "${EZ_DATA}/web/nginx-frontend.conf"
fi
