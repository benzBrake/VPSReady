#!/usr/bin/env sh
# find_large_files.sh - 查找指定目录下的大文件
# 用法: source .utils/find_large_files.sh && find_large_files [目录] [大小阈值MB]

# 自动加载 common.sh
# 尝试多种方式获取脚本目录，兼容 source 和直接执行
_get_script_dir() {
    _dir="${0%/*}"
    if [ "${_dir}" = "${0}" ] || [ -z "${_dir}" ]; then
        _dir="$(pwd)"
    else
        _dir="$(cd "${_dir}" && pwd)"
    fi
    printf '%s' "${_dir}"
}

_SCRIPT_DIR="$(_get_script_dir)"

# 尝试加载 common.sh
if [ -f "${_SCRIPT_DIR}/common.sh" ] && ! type info >/dev/null 2>&1; then
    . "${_SCRIPT_DIR}/common.sh"
fi

# 如果上面加载失败，尝试从项目根目录加载
if ! type info >/dev/null 2>&1; then
    if [ -f "./.utils/common.sh" ]; then
        . "./.utils/common.sh"
    fi
fi

unset _get_script_dir _dir _SCRIPT_DIR

find_large_files() {
    # 参数处理
    SEARCH_DIR="${1:-.}"
    SIZE_MB="${2:-100}"

    # 验证目录存在
    if [ ! -d "${SEARCH_DIR}" ]; then
        err "目录不存在: ${SEARCH_DIR}"
        return 1
    fi

    info "正在搜索 ${SEARCH_DIR} 下大于 ${SIZE_MB}MB 的文件..."

    # 将 MB 转换为 KB（find -size 只支持整数和 k/M/G 单位）
    # 小于 1MB 的转换为 KB，大于等于 1MB 的使用 MB
    SIZE_KB=$(awk "BEGIN {printf \"%d\", ${SIZE_MB} * 1024}")
    if [ "${SIZE_KB}" -lt 1024 ]; then
        SIZE_SPEC="+${SIZE_KB}k"
    else
        SIZE_MB_INT=$(awk "BEGIN {printf \"%d\", ${SIZE_MB}}")
        SIZE_SPEC="+${SIZE_MB_INT}M"
    fi

    # 查找大文件并格式化输出
    find "${SEARCH_DIR}" \
        -type f \
        -size "${SIZE_SPEC}" \
        -exec du -sh {} \; \
        2>/dev/null | \
        sort -rh | \
        awk -v size_limit="${SIZE_MB}" '
        BEGIN {
            print "============================================================"
            printf "%-12s %s\n", "大小", "路径"
            print "============================================================"
            count = 0
            total = 0
        }
        {
            size_str = $1
            $1 = ""
            path = substr($0, 2)

            # 保存原始大小用于显示
            size_display = size_str

            # 转换大小为MB
            if (size_str ~ /G$/) {
                gsub(/G/, "", size_str)
                size_mb = size_str * 1024
            } else if (size_str ~ /M$/) {
                gsub(/M/, "", size_str)
                size_mb = size_str + 0
            } else if (size_str ~ /K$/) {
                gsub(/K/, "", size_str)
                size_mb = size_str / 1024
            } else {
                size_mb = size_str / 1024 / 1024
            }

            printf "%-12s %s\n", size_display, path
            count++
            total += size_mb
        }
        END {
            print "============================================================"
            printf "找到 %d 个文件，总大小: %.2f MB\n", count, total
            if (total >= 1024) {
                printf "约 %.2f GB\n", total / 1024
            }
        }'

    # 检查命令执行结果
    if [ $? -ne 0 ]; then
        err "查找过程中出现错误"
        return 1
    fi

    return 0
}

# 如果直接执行此脚本
if [ "${0##*/}" = "find_large_files.sh" ]; then
    find_large_files "$@"
fi
