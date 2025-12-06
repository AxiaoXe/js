#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

# 要插入的 location 内容，使用单引号保护所有特殊字符，防止 sed 解析出错
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
        proxy_pass https://xzz.pier46.com;
    }
EOF

echo "开始处理 Nginx 配置文件..."

# 遍历所有 .conf 文件
for file in "$NGINX_DIR"/*.conf; do
    # 判断文件是否存在（避免通配符未匹配时出现字面量问题）
    [[ -f "$file" ]] || continue

    echo "处理文件: $file"

    # 方法1：使用 sed 的 a 命令插入多行内容（推荐，最安全）
    # -i 后缀为空表示直接编辑原文件，兼容 GNU 和 BSD sed
    sed -i'' "/server_name/a\\
$LOCATION_BLOCK
" "$file"

    # 如果上面在某些系统（如纯 BSD）报错，可改用以下更兼容的写法（已注释备用）：
    # printf '%s\n' '/server_name/a' "$LOCATION_BLOCK" '.' 'w' | ed -s "$file"
done

echo "所有文件插入完成，正在校验配置并重启 nginx..."

# 先测试配置是否正确
if nginx -t > /dev/null 2>&1; then
    # 配置正确，优雅重启
    nginx -s reload && echo "nginx 配置校验通过，已优雅重载"
else
    echo "ERROR: nginx 配置校验失败！请手动检查配置文件，已终止重启操作"
    nginx -t  # 输出详细错误
    exit 1
fi

echo ""
echo "==== 当前所有 server_name 列表 ===="
grep -R "server_name" -n --color=auto "$NGINX_DIR" | grep -v "^#" || true

echo ""
echo "脚本执行完毕"
