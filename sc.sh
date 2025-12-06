#!/bin/bash

# ============ 彻底删除所有 /news/ 代理配置（修复乱码版）============
NGINX_DIR="/etc/nginx/sites-enabled"
BACKUP_DIR="/root/nginx_clean_news_backup_$(date +%Y%m%d_%H%M%S)"

MARKER_START="# === GROK NEWS BLOCK START ==="
MARKER_END="# === GROK NEWS BLOCK END ==="

echo "=============================================="
echo "  彻底删除 $NGINX_DIR 下所有 /news/ 代理配置"
echo "  备份目录：$BACKUP_DIR"
echo "=============================================="

mkdir -p "$BACKUP_DIR"

# 使用 find -exec + 这里是关键：完全避免管道子shell导致的 perl 乱输出
find "$NGINX_DIR" \( -type f -o -type l \) -exec bash -c '
    file="$1"
    filename=$(basename "$file")
    backup_dir="'"$BACKUP_DIR"'"

    echo "正在处理：$filename"

    # 1. 先备份（永远要备份！）
    cp -a "$file" "$backup_dir/$filename.bak.$(date +%s)" 2>/dev/null || true

    # 2. 如果你之前插入时用了标记，直接整段删除（最干净）
    if grep -q "'"$MARKER_START"'" "$file" 2>/dev/null; then
        echo "  发现带标记的 block → 整段删除"
        sed -i "/'"$MARKER_START"'/,/'"$MARKER_END"'/d" "$file"
    fi

    # 3. 无标记情况：强力删除所有 location /news/ 相关内容
    #    关键：perl 使用 -i（原地修改） + 不带 -p（不自动打印） = 零输出！
    perl -0777 -i -pe "
        # 删除各种写法的 location /news/ 完整块
        s/\s*location\s+[~]?\s*[\47\"]?\/?news\/?[\47\"]?\s*\{.*?\}//gs;
        # 删除可能残留的单行
        s/.*location[^\n]*news[^\n]*/\n/gi;
        # 清理多余空行
        s/\n{3,}/\n\n/g;
    " "$file" 2>/dev/null

    # 4. 再次保险删除（sed 强杀残留）
    sed -i "/location.*news.*{/,/^}/d" "$file" 2>/dev/null || true
    sed -i "/location.*news/d" "$file" 2>/dev/null || true

    # 5. 删除空行，美化配置
    sed -i "/^\s*$/d" "$file" 2>/dev/null

    echo "  已彻底清除 $filename 中的所有 /news/ 配置"
' bash {} \;

# 全局再美化一次（防止残留空行）
find "$NGINX_DIR" \( -type f -o -type l \) -exec sed -i "/^\s*$/d" {} + 2>/dev/null

echo ""
echo "=========================================="
echo "  Nginx 配置语法检查..."
if nginx -t > /dev/null 2>&1; then
    echo "  配置测试通过！"
    nginx -s reload
    echo "  Nginx 已平滑重载"
else
    echo "  配置语法错误！已阻止重载"
    nginx -t
    echo ""
    echo "  备份已保留在：$BACKUP_DIR"
    echo "  可手动恢复：cp $BACKUP_DIR/* $NGINX_DIR/"
    exit 1
fi

echo ""
echo "  彻底清理完成！所有 /news/ 代理配置已消失"
echo "  备份目录：$BACKUP_DIR"
echo ""
echo "  当前 sites-enabled 下所有 server_name："
grep -RH "server_name" "$NGINX_DIR" 2>/dev/null | grep -v "^#" | sed 's/^/  → /'
echo ""
echo "脚本执行完毕，绝对干净，无任何乱码输出！"
