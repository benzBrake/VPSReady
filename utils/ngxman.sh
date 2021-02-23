#!/bin/bash
###
 # @Author: Ryan
 # @Date: 2021-02-22 20:18:53
 # @LastEditTime: 2021-02-23 15:08:23
 # @LastEditors: Ryan
 # @Description: Docker Nginx 管理脚本
 # @FilePath: \VPSReady\utils\ngxman.sh
 # Mod From https://github.com/tahaHichri/nginxse-virtualhost-generator/blob/master/nginxse.sh
###
# OS destribution
DESPCN=$(lsb_release -si)

# try locating NGINX install dir
NGXInstallDir="/data/web"
NGXCfgDir="/conf.d"
NGXExtDir="/extra"
NGXRwtDir="/rewrite"
NGXWebDir="/webapps"
NGXCrtDir="/webssls"

# docker-compose config file
CMPFileDir="/data/docker-compose.yml"

# Prepare php enable config
if [ ! -f "${NGXInstallDir}${NGXExtDir}/enable-php.conf" ]; then
  cat >"${NGXInstallDir}${NGXExtDir}/enable-php.conf" <<EOF
location ~ \.php\$ {
    include /etc/nginx/fastcgi_params;
    fastcgi_pass php:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
}
EOF
fi

# Prepare php pathinfo enable config
if [ ! -f "${NGXInstallDir}${NGXExtDir}/enable-php-pathinfo.conf" ]; then
  cat >"${NGXInstallDir}${NGXExtDir}/enable-php-pathinfo.conf" <<EOF
location ~ [^/]\.php(/|\$) {
    #listen tcp socket
    fastcgi_pass  php:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

    #pathinfo
    fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
    set \$path_info \$fastcgi_path_info;
    fastcgi_param PATH_INFO \$path_info;
    try_files \$fastcgi_script_name =404;
}
EOF
fi

# Prepare typecho rewrite rule
# Typecho
if [ ! -f "${NGXInstallDir}${NGXRwtDir}/typecho.conf" ]; then
  cat >${NGXInstallDir}${NGXRwtDir}/typecho.conf <<EOF
if (!-e \$request_filename) {
    rewrite ^(.*)\$ /index.php$1 last;
}
EOF
fi
# WordPress
if [ ! -f "${NGXInstallDir}${NGXRwtDir}/wordpress.conf" ]; then
  cat >${NGXInstallDir}${NGXRwtDir}/wordpress.conf <<EOF
location / {
    if (-f \$request_filename/index.html){
        rewrite (.*) $1/index.html break;
    }
    if (-f \$request_filename/index.php){
        rewrite (.*) $1/index.php;
    }
    if (!-f \$request_filename){
        rewrite (.*) /index.php;
    }
}
EOF
fi

# display notice and call for check.
function landingNotice() {
  rows=$(tput lines)
  cols=$(tput cols)
  fallbackNotice="Welcome to HostMan on $DESPCN\n"
  middle_row=$((rows / 2))
  middle_col=$((cols / 2))
  tput clear
  tput cup $middle_row $middle_col
  tput bold
  echo -e "$fallbackNotice"
  echo -e "This script will help you manage NGINX Server Block config Files.\n"
  echo -e "This is a free, open-source software originally released by hishri.com\n"
  echo -e "IMPORTANT: -The script WILL NOT delete/modify any existing config files"
  echo -e "       -You will be promped before any steps will be made."
  tput sgr0
  tput cup "$(tput lines)" 0
}

function index() {
  clear
  landingNotice
  echo  "Functions:"
  echo  "1.Add Virtual Host"
  echo  "2.Del Virtual Host"
  echo  "3.Check Nginx Conf"
  echo  "4.Restart Nginx"
  echo  "Q.Exit"

  read -p "[S] Your Choice:" choice
  case "$choice" in
    1)
      addHost
      index
      ;;
    2)
      delHost
      index
      ;;
    3)
      checkConf
      index
      ;;
    4)
      restartNginx
      index
      ;;
    q | Q)
      exit 0
      ;;
    *)
      anykey "[W] Choose nothing... Press any key to continue."
      index
      ;;
  esac
}

function addHost() {
  # ask for server name
  read -p "[Q] Server name(s) (e.g., example.com or sub.example.com):   " server_name
  if [ -f "${NGXInstallDir}${NGXCfgDir}/${server_name}.conf" ]; then
    read -p "[Q] Config file exists, replace? (y/N):  " replace_flag
    case "${replace_flag}" in
    y | Y) echo -e "[I] OK! Config file will be replaced." ;;
    *) echo -e "[I] Nothing to do." && index ;;
    esac
  fi
  read -p "[Q] Html files directory absolute path (default: ${NGXInstallDir}${NGXWebDir}/${server_name}):  " server_root
  echo -e "[Q] Are you using PHP-FPM:\nPHP-FPM can be installed and set a default\nPHP-FPM is usually set in /etc/php-fpm.d/www.conf."
  read -p "[Q] Enable PHP Support? (Y/n):  " php_support
  read -p "[Q] Enable Pathinfo Support? (Y/n):  " pathinfo_support
  echo "[I] Support Rewrite Rules:"
  find "${NGXInstallDir}${NGXRwtDir}" -name "*.conf" | sed 's#.*/##' | sed "s#.conf##g"
  read -p "[Q] Choose your rewrite rules (Enter to skip or input the rewrite rule name)?:  " rewrite_support

  # set default document root
  if [ -z "${server_root}" ]; then
    server_root="${NGXInstallDir}${NGXWebDir}/${server_name}"
  fi

  # enable php support
  case "${php_support}" in
  n | N) echo -p "[I] N is selected, Ignoring PHP" ;;
  *)
    case "${pathinfo_support}" in
    n | N)
      phpblock="# Enable php
    include ${NGXInstallDir}${NGXExtDir}/enable-php.conf;"
      ;;
    *)
      phpblock="# Enable php with pathinfo support
    include ${NGXInstallDir}${NGXExtDir}/enable-php-pathinfo.conf;"
      ;;
    esac
    ;;
  esac

  # set rewrite rules
  if [ -z "${rewrite_support}" ]; then
    echo "[I] Rewrite rule not selected."
    rewriteblock=""
  else
    if [ -f "${NGXInstallDir}${NGXRwtDir}/${rewrite_support}.conf" ]; then
      rewriteblock="# Enable Rewrite
    include ${NGXInstallDir}${NGXRwtDir}/${rewrite_support}.conf;"
    else
      echo "[W] Rewrite rules not exists, skipped!"
      rewriteblock=""
    fi
  fi

  # detect ssl certificate
  if [ -f "${NGXInstallDir}${NGXCrtDir}/${server_name}.crt" ] && [ -f "${NGXInstallDir}${NGXCrtDir}/${server_name}.key" ]; then
    sslblock="#SSL Configuration
    listen 443 ssl;
    ssl_certificate ${NGXInstallDir}${NGXCrtDir}/${server_name}.crt;
    ssl_certificate_key ${NGXInstallDir}${NGXCrtDir}/${server_name}.key;
    ssl_session_timeout 5m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
    ssl_prefer_server_ciphers on;\n"
  else
    sslblock=""
  fi

  serverblock="
server {
    listen 80 ;
    listen [::]:80 ;
    server_name ${server_name};

    ${sslblock}

    root ${server_root};
    # Add index.php to the list if you are using PHP
    index index.php index.html index.htm index.nginx-debian.html;
    location / {
      try_files \$uri \$uri/ =404;
    }
       
    ${phpblock}

    ${rewriteblock}
}"

  echo -e "[S] Server block succesfully generated!
[I] You can save the generated configuration into a new (.conf) file
[I] Server block configuration file to create: '${NGXInstallDir}${NGXCfgDir}/${server_name}.conf'"
  read -p "[Q] Create and Save '${server_name}.conf'? (Y/n) if you choose 'N' the config will be displayed.  " savefile

  case "$savefile" in
  n | N) echo -e "${serverblock}" ; anykey ;;
  *)
    echo -e "$serverblock" >"${NGXInstallDir}${NGXCfgDir}/${server_name}.conf"
    if [ -f "${NGXInstallDir}${NGXCfgDir}/${server_name}.conf" ]; then
      echo -e "[S] Replace complete.\n[success] ${NGXInstallDir}${NGXCfgDir}/${server_name}.conf has been successfully created!"
      echo -e "[Q] Checking configuration files ..."
      if checkConf; then
        echo "[C] Configuration seems to be ok."
      else
        echo "[S] Configuration seems to be ok. Nginx will be restarted."
        restartNginx
      fi
    fi
    ;;
  esac
}

function delHost() {
  echo "[I] Still in development"
}

function checkConf() {
  docker-compose -f ${CMPFileDir} exec nginx nginx -t
  err=$?
  anykey
  return ${err}
}

function restartNginx {
  docker-compose -f ${CMPFileDir} restart nginx
  err=$?
  anykey
  return ${err}
}

function anykey() {
  MSG=${1-[S] Press any key to confinue...}
  read -p "${MSG}"
}

index
