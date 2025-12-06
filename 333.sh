#!/bin/sh

# 1. 创建目录
mkdir -p /etc/nginx/global

# 2. 写入 news.conf
cat > /etc/nginx/global/news.conf << 'EOF'
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

# 3. 在 nginx.conf 中插入 include（如果不存在）
if ! grep -q "include /etc/nginx/global/\*.conf;" /etc/nginx/nginx.conf; then
    sed -i '/http {/a\    include /etc/nginx/global/*.conf;' /etc/nginx/nginx.conf
    echo "已写入 include 到 nginx.conf"
else
    echo "nginx.conf 已存在 include，无需重复写入"
fi

# 4. 测试并重启 nginx
nginx -t && systemctl restart nginx

echo "全部完成！ news.conf 已生效。"
