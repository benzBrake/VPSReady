#!/bin/sh
randomNum() {
    awk -v min=10000 -v max=99999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}
info() {
    echo "[I] $*" >&2
}
warn() {
    echo "[W] $*" >&2
}
err() {
    echo "[E] $*" >&2
}
suc() {
    echo "[S] $*" >&2
}
