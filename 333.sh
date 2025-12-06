#!/bin/sh

CONF="/etc/nginx/nginx.conf"
INCLUDE="include /etc/nginx/global/*.conf;"

# 1. 删除所有错误位置的 include（http{} 外）
sed -i "/$INCLUDE/d" "$CONF"

# 2. 确保 http { 后插入 include
sed -i "/http {/a\    $INCLUDE" "$CONF"

echo "✔ 已修复 include 位置，重新测试 nginx 配置..."

# 3. 测试 nginx 配置
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ 配置仍有问题，请把 nginx.conf 内容发我，我帮你修复"
    exit 1
fi

# 4. 重启 Nginx
systemctl restart nginx 2>/dev/null || service nginx restart

echo "🎉 修复完成！nginx 已成功加载 global/news.conf"
