#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 要插入的 location 内容（EOF 保持缩进）
read -r -d '' LOCATION_BLOCK << 'EOF'
    location /news/ {

        # 构造完整域名URL，例如 https://abc.com/news/xxx
        set $fullurl "$scheme://$host$request_uri";

        # 重写并保留原有参数
        rewrite ^/news/?(.*)$ /index.php?domain=$fullurl&$args break;

        # 后端真实主机
        proxy_set_header Host xzz.pier46.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header User-Agent $http_user_agent;
        proxy_set_header Referer $http_referer;

        proxy_ssl_server_name on;

        # 正确的 HTTPS upstream 写法
        proxy_pass http://xzz.pier46.com;
    }
EOF

echo "开始处理 Nginx 配置文件..."

for file in "$NGINX_DIR"/*.conf; do
    echo "处理文件: $file"

    # 在 server_name 行后插入 location block
    sed -i "/server_name/a $LOCATION_BLOCK" "$file"
done

echo "插入完成，重启 nginx..."

# 强行 kill nginx
pkill nginx

# 再重新启动 nginx
nginx

echo "nginx 已重启"
echo ""
echo "==== 所有 server_name 列表 ===="

grep -R "server_name" -n $NGINX_DIR
