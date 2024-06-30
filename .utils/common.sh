#!/bin/bash
randomNum() {
    awk -v min=10000 -v max=99999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}
info() {
    echo "[I] $*"
}
warn() {
    echo "[W] $*"
}
err() {
    echo "[E] $*"
}
suc() {
    echo "[S] $*"
}
