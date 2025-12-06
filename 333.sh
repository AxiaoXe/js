#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 生成临时文件保存 location block
TMPFILE=$(mktemp)

cat > "$TMPFILE" << 'EOF'
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

echo "开始插入 location..."

for file in "$NGINX_DIR"/*.conf; do
    echo "处理文件: $file"

    # 在 server_name 行后插入 TMPFILE 内容
    sed -i "/server_name/r $TMPFILE" "$file"
done

# 删除临时文件
rm -f "$TMPFILE"

echo "插入完成，重启 Nginx..."

pkill nginx
nginx

echo "==== 当前 server_name 列表 ===="
grep -R "server_name" -n $NGINX_DIR
