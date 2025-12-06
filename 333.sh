#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 多行内容写入变量
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


echo "开始插入..."

for file in $NGINX_DIR/*.conf; do
    echo "处理：$file"

    awk -v block="$BLOCK" '
        /server_name/ {
            print;
            print block;
            next;
        }
        { print }
    ' "$file" > "$file.tmp"

    mv "$file.tmp" "$file"
done

echo "插入完成，重启 nginx..."

pkill nginx
nginx

echo "==== 所有 server_name 列表 ===="
grep -R "server_name" -n /etc/nginx/sites-enabled
