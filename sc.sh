#!/bin/bash
# 文件名：clean_nginx_hidden_locations.sh
# 功能：一键彻底删除所有之前脚本生成的隐蔽 location（支持 .com/.in 所有路径）
# 作者：2025 终极清理版

NGINX_DIR="/etc/nginx/sites-enabled"

# 我们用过的所有隐蔽路径（一定要和生成脚本里的一模一样）
COM_PATHS=("help" "news" "page" "blog" "bangzhuzhongxin" "zh" "pc" "support" "info" "about")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")
ALL_PATHS=("${COM_PATHS[@]}" "${IN_PATHS[@]}")

echo "开始清理所有隐蔽 location 块..."
echo "============================================================================"

# 构建正则表达式：location /help/  或 /pg/  或 /blog/ 等
PATH_REGEX=$(printf "|/%s/" "${ALL_PATHS[@]}")
PATH_REGEX=${PATH_REGEX:1}  # 去掉开头的 |

changed_files=0

for file in "$NGINX_DIR"/*; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")

    # 如果文件里压根没有我们关心的路径，直接跳过
    if ! grep -qE "location /$PATH_REGEX/" "$file" && ! grep -qE 'xzz\.pier46\.com|ide\.hashbank8\.com' "$file"; then
        continue
    fi

    echo "正在清理 → $filename"

    # 方法：删除从 location /xxx/ 开始到匹配的 } 为止的整个块
    # 同时包含我们后端域名或 index.php?domain= 的特征
    perl -0777 -i -pe '
        s/\n?\s*location\s+\/(?:'"${ALL_PATHS[*]// /|}"')\/.*?\{.*?(?:xzz\.pier46\.com|ide\.hashbank8\.com|index\.php\?domain=).*?\n\s*\}[ \t]*\n?//gs;
        s/\n{3,}/\n\n/g;  # 清理多余空行
    ' "$file"

    # 再保险一次：删除任何残留包含我们后端的 location
    sed -i '/xzz\.pier46\.com\|ide\.hashbank8\.com\|index\.php?domain=/{
        /^[\t ]*location/d
        N; /}/!D; /}/d
    }' "$file"

    # 删除可能产生的空行
    sed -i '/^[[:space:]]*$/d' "$file"

    ((changed_files++))
done

echo "============================================================================"
if [[ $changed_files -gt 0 ]]; then
    echo "已清理 $changed_files 个配置文件"
else
    echo "未发现需要清理的内容，配置已是干净状态"
fi

# 校验并重载
echo "正在校验 Nginx 配置..."
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null
    echo -e "\033[32m清理完成！Nginx 已平滑重载，配置已恢复原始干净状态！\033[0m"
else
    echo -e "\033[31mNginx 配置错误！请手动执行 nginx -t 查看\033[0m"
    nginx -t
    exit 1
fi

echo -e "\n现在可以放心重新运行生成脚本，路径会重新随机分配，毫无痕迹！\n"
exit 0
