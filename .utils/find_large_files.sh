#!/bin/bash
# find_large_files.sh - 查找指定目录下的大文件
# 用法: source .utils/find_large_files.sh && find_large_files [目录] [大小阈值MB]

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

    # 查找大文件并格式化输出
    find "${SEARCH_DIR}" \
        -type f \
        -size "+${SIZE_MB}M" \
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

            printf "%-12s %s\n", size_str, path
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
