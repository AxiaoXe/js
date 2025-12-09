#!/bin/bash
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

function clean_quotes(str) {
    # 更安全的方式：使用字符类 [\047"] 或直接写两种引号
    gsub(/[\047"]/, "", str)  # \047 是单引号的八进制表示
    return str
}

function normalize_path(p) {
    p = clean_quotes(p)
    gsub(/[\/]+$/, "", p)
    if (p == "") p = "/"
    return p
}

function process_proxy_pass(val,   b, host, path, i, a) {
    b = trim(val)
    if (b ~ /^https?:\/\//) {
        sub(/^https?:\/\//, "", b)
        split(b, a, "/")
        host = a[1]
        path = ""
        for (i = 2; i <= length(a); i++) {
            if (a[i] != "") path = path "/" a[i]
        }
        gsub(/\/+$/, "", path)
        return host (path == "" ? "" : "/" path)
    }
    return b
}

{
    if (process($0)) next
}

function process(line,   inc, cmd, f, inc_line, path, backend, d, doms, i) {
    line = trim(line)
    if (line == "" || substr(line, 1, 1) == "#") return 1

    # 处理 include（宝塔大量使用）
    if (line ~ /^[ \t]*include[ \t]/) {
        sub(/^[ \t]*include[ \t]+/, "", line)
        gsub(/[;\r].*$/, "", line)
        inc = trim(line)
        if (inc !~ /^\// && FILENAME ~ /\//) inc = FILENAME "/../" inc
        if (inc ~ /[\*\[\?]/) {
            cmd = "ls -1 " inc " 2>/dev/null"
            while ((cmd | getline f) > 0) {
                if (f != FILENAME) {
                    while ((getline inc_line < f) > 0) process(inc_line)
                    close(f)
                }
            }
            close(cmd)
        } else if (inc != "") {
            while ((getline inc_line < inc) > 0) process(inc_line)
            close(inc)
        }
        return 1
    }

    # server_name
    if (line ~ /^[ \t]*server_name[ \t]/) {
        sub(/^[ \t]*server_name[ \t]+/, "", line)
        gsub(/#.*/, "", line)
        split(trim(line), doms, /[ \t]+/)
        delete current_domains
        for (i in doms) {
            d = trim(doms[i])
            if (d != "" && d != "_") current_domains[d] = 1
        }
        return 1
    }

    if (line ~ /^[ \t]*server[ \t]*{/) { delete current_domains; return 1 }
    if (line ~ /^[ \t]*}[ \t]*$/)     { delete current_domains; return 1 }

    # location 块
    if (line ~ /^[ \t]*location[ \t]*[=~^~ ]/) {
        # 提取 location 后面的路径（最稳方式：先整体切，再清理引号）
        if (match(line, /^[ \t]*location[ \t]*[=~^~ ]*[ \t]*[^ \t{;]+/)) {
            path = substr(line, RSTART, RLENGTH)
            path = trim(path)
            path = normalize_path(path)

            # 同行的 proxy_pass
            if (index(line, "proxy_pass") && match(line, /proxy_pass[ \t]+[^;{}]+/)) {
                backend = substr(line, RSTART + 11, RLENGTH - 11)
                backend = trim(backend)
                backend = process_proxy_pass(backend)
                if (backend != "") output(path, backend)
                return 1
            }

            # 跨行 proxy_pass
            saved_path = path
            while (getline > 0) {
                $0 = trim($0)
                if ($0 ~ /^[ \t]*}/) break
                if (substr($0,1,1) == "#") continue
                if (index($0, "proxy_pass")) {
                    sub(/.*proxy_pass[ \t]+/, "", $0)
                    gsub(/[;\r].*$/, "", $0)
                    backend = process_proxy_pass(trim($0))
                    if (backend != "") output(saved_path, backend)
                    break
                }
            }
        }
    }
    return 1
}

function output(p, b) {
    if (p == "" || b == "" || length(current_domains) == 0) return
    for (d in current_domains) {
        printf "%-50s → %-40s → %s\n", d, p, b
    }
}

BEGIN { delete current_domains }
' | sort -u
