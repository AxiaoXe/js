#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 要插入的 location 块（完全避免 sed 直接解析任何 $ / & 等特殊字符）
read -r -d '' LOCATION_BLOCK << 'EOF'
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

for file in "$NGINX_DIR"/*.conf; do
    [[ -f "$file" ]] || continue
    echo "处理文件: $file"

    # 方案三：使用 awk 完全绕过 sed 的正则噩梦，100% 兼容所有 $ / & \ 字符
    awk -v block="$LOCATION_BLOCK" '
    {
        print $0
        if (/^[[:blank:]]*server_name[[:blank:]]/) {
            print block
            print ""  # 插入空行，美观点
        }
    }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

done

echo "所有文件插入完成，正在校验配置并重启 nginx..."

if nginx -t > /dev/null 2>&1; then
    nginx -s reload
    echo "nginx 配置校验通过，已优雅重载"
else
    echo "ERROR: nginx 配置校验失败！请立即检查以下错误："
    nginx -t
    exit 1
fi

echo ""
echo "==== 当前所有 server_name 列表 ===="
grep -R "server_name" -n --color=auto "$NGINX_DIR" | grep -v "^[[:blank:]]*#" || true

echo ""
echo "脚本执行完毕（本次使用 awk 方式，彻底杜绝 sed 特殊字符问题）"
