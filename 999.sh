#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 随机目录列表
DIRS=(news bangzuzhongxin shiyongjiaocheng zh en m page pages)

# 为每个 server_name 生成一个随机目录
declare -A SERVER_DIR_MAP

echo ""
echo "===== 开始为每个 server_name 随机生成独立目录 ====="
echo ""

###########################################################
# 函数：生成随机目录
###########################################################
generate_random_dir() {
    echo "${DIRS[$RANDOM % ${#DIRS[@]}]}"
}

###########################################################
# 函数：为给定 server_name 生成 block
###########################################################
make_block() {
    local dir="$1"
    cat << EOF
    location /$dir/ {
        set \$fullurl "\$scheme://\$host\$request_uri";
        rewrite ^/$dir/?(.*)$ /index.php?domain=\$fullurl&\$args break;
        proxy_set_header Host xzz.pier46.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header User-Agent \$http_user_agent;
        proxy_set_header Referer \$http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://xzz.pier46.com;
    }

EOF
}

###########################################################
# 主流程：扫描所有 server_name
###########################################################
for file in "$NGINX_DIR"/*.conf; do
    [[ -f "$file" ]] || continue

    while read -r line; do
        # 提取 server_name 内容
        if [[ "$line" =~ server_name[[:space:]]+([^;]+) ]]; then
            names=${BASH_REMATCH[1]}

            for name in $names; do
                if [[ -z "${SERVER_DIR_MAP[$name]}" ]]; then
                    SERVER_DIR_MAP[$name]=$(generate_random_dir)
                fi
            done
        fi
    done < "$file"
done

###########################################################
# 输出随机生成结果
###########################################################
echo "==== 已生成的 server_name → 随机目录 映射表 ===="
for name in "${!SERVER_DIR_MAP[@]}"; do
    echo "$name → ${SERVER_DIR_MAP[$name]}"
done
echo ""

###########################################################
# 插入 block 的函数们 (与原脚本一致)
###########################################################

try_insert_block() {
    local file="$1"
    local name="$2"
    local dir="${SERVER_DIR_MAP[$name]}"
    local block
    block="$(make_block "$dir")"

    local tmp_block=$(mktemp)
    printf "%s\n" "$block" > "$tmp_block"

    # 方式1：sed r
    sed -i "/server_name.*$name/r $tmp_block" "$file" 2>/dev/null && return 0

    # 方式2：sed 多行插入
    local escaped
    escaped=$(printf '%s\n' "$block" | sed 's/[&/\]/\\&/g')
    sed -i "/server_name.*$name/a $escaped" "$file" 2>/dev/null && return 0

    # 方式3：awk
    local tmp=$(mktemp)
    awk -v key="$name" -v block="$block" '
        {
            print $0
            if ($0 ~ ("server_name[[:space:]].*" key)) {
                print block
                print ""
            }
        }' "$file" > "$tmp"
    mv "$tmp" "$file" && return 0

    # 方式4：perl
    BLOCK="$block" perl -0777 -i -pe "
        s/(server_name[^;]*$name[^;]*;)/\$1\n\$ENV{BLOCK}\n/g;
    " "$file" && return 0

    # 方式5：shell fallback
    local tmp2=$(mktemp)
    while read -r line; do
        echo "$line" >> "$tmp2"
        if [[ "$line" =~ server_name.*$name ]]; then
            echo "$block" >> "$tmp2"
        fi
    done < "$file"

    mv "$tmp2" "$file" && return 0

    return 1
}

###########################################################
# 插入 block 到每个配置文件
###########################################################

echo "===== 开始写入 nginx 配置 ====="
echo ""

for file in "$NGINX_DIR"/*.conf; do
    [[ -f "$file" ]] || continue
    echo "处理文件：$file"

    for name in "${!SERVER_DIR_MAP[@]}"; do
        if grep -q "server_name.*$name" "$file"; then
            echo "  为 server_name: $name 插入目录：${SERVER_DIR_MAP[$name]}"
            try_insert_block "$file" "$name"
        fi
    done

    echo ""
done

###########################################################
# 检查 nginx 配置
###########################################################

echo ""
echo "正在校验 nginx 配置..."

if nginx -t > /dev/null 2>&1; then
    nginx -s reload
    echo "✔ 配置正常，已 reload Nginx"
else
    echo "❌ nginx 配置异常，请检查："
    nginx -t
    exit 1
fi

echo ""
echo "脚本执行完毕。"
