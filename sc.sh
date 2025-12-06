#!/bin/bash
# 文件名: delete_server_name_9lines.sh
# 用法: sudo ./delete_server_name_9lines.sh [--dry-run]

set -euo pipefail

DIR="/etc/nginx/sites-enabled"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== 干跑模式：仅显示将要删除的内容，不会实际修改文件 ==="
fi

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
    echo "请用 sudo 运行此脚本"
    exit 1
fi

# 统计将要处理的文件数量
file_count=$(find "$DIR" -type f ! -name "*.bak*" | wc -l)
if [[ $file_count -eq 0 ]]; then
    echo "没有找到配置文件，退出。"
    exit 0
fi

echo "即将处理目录: $DIR"
echo "找到 $file_count 个配置文件"
if [[ $DRY_RUN == false ]]; then
    echo "操作将："
    echo "   1. 备份原文件 → 原文件名${BACKUP_SUFFIX}"
    echo "   2. 删除每一个 server_name 行 + 其后连续9行（共10行）"
    read -p "确认继续？(输入 y/Y 继续): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

echo ""
echo "正在处理..."

find "$DIR" -type f ! -name "*.bak*" | sort | while read -r file; do
    if ! grep -q "server_name" "$file"; then
        continue
    fi

    if [[ $DRY_RUN == true ]]; then
        echo "=== $file 将被修改 ==="
        # 显示将被删除的行（带行号）
        grep -n "server_name" "$file" | cut -d: -f1 | while read -r line; do
            echo "删除行 $line 到 $((line+9))："
            sed -n "${line},${((line+9))}p" "$file" | cat -n
            echo "---"
        done
        echo ""
        continue
    fi

    # 正式执行：备份 + 删除
    cp "$file" "${file}${BACKUP_SUFFIX}"
    sed -i '/server_name/{N;N;N;N;N;N;N;N;N;d;}' "$file"
    echo "已处理: $file  (备份: ${file}${BACKUP_SUFFIX})"
done

if [[ $DRY_RUN; then
    echo "=== 干跑结束 ==="
    exit 0
fi

echo ""
echo "所有文件处理完成！"
echo "正在校验 Nginx 配置..."
if nginx -t > /dev/null 2>&1; then
    echo "Nginx 配置测试通过 ✓"
    read -p "是否立即重载 Nginx？(y/N): " reload
    if [[ "$reload" =~ ^[yY]$ ]]; then
        systemctl reload nginx && echo "Nginx 已重载"
    fi
else
    echo "Nginx 配置有语法错误！请检查修改内容"
    echo "可使用备份文件恢复："
    echo "   cp ${DIR}/*${BACKUP_SUFFIX} ${DIR}/"
    exit 1
fi

echo ""
echo "完成！备份文件后缀：${BACKUP_SUFFIX}"
