#!/bin/bash
echo "域名                                      → 注入路径                          → 后端真实地址"
echo "================================================================================================================"

# 只扫你指定的这三个目录（绝不多扫一个文件）
find /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/nginx/sites-available -type f 2>/dev/null | \
xargs -r awk '
function trim(s) {gsub(/^[ \t\r]+|[ \t\r;]+$/, "", s); return s}

function normalize_path(p) {
    gsub(/["'\'']/, "", p)          # 去掉可能残留的引号
    gsub(/[\/]+$/, "", p)
    if (p == "") p = "/"
    return p
}

function process_proxy_pass(val,    b, scheme, host, path) {
    b = trim(val)
    if (b ~ /^https?:\/\//) {
        sub(/^https?:\/\//, "", b)
        split(b, a, "/")
        host = a[1]
        delete a[1]
        path = "/" join(a, "/")
        if (path == "/") path = ""
        return host path
    }
    return b
}

# 数组拼接辅助（awk 没有内置 join）
function join(arr, sep,   result, i) {
    result = ""
    for (i = 1; i <= length(arr); i++) {
        if (i > 1) result = result sep
        result = result arr[i]
    }
    return result
}

{
    if (process($0)) next
}

function process(line,    inc, cmd, f, inc_line, m, path, backend, domains_str) {
    line = trim(line)
    if (line == "" || substr(line,1,1) == "#") return 1

    # 递归处理 include（支持 *.conf、通配符、多层嵌套）
    if (line ~ /^[ \t]*include[ \t]/) {
        sub(/.*include[ \t]+/, "", line)
        gsub(/[;\r].*$/, "", line)
        inc = trim(line)

        if (inc !~ /^\// && FILENAME ~ /\//) {
            inc = FILENAME "/../" inc
        }

        if (inc ~ /[\*\[\?]/) {                   # 支持通配符
            cmd = "ls " inc " 2>/dev/null"        # 用 ls 更稳（find 在某些系统会乱序）
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

    # 收集 server_name
    if (line ~ /^[ \t]*server_name[ \t]/) {
        gsub(/.*server_name[ \t]+/, "", line)
        gsub(/#.*/, "", line)
        split(trim(line), doms, /[ \t]+/)
        delete current_domains
        for (i in doms) if ((d=trim(doms[i])) != "" && d != "_") current_domains[d] = 1
        return 1
    }

    # server 块开始/结束 清空域名作用域
    if (line ~ /^[ \t]*server[ \t]*{/) { delete current_domains; return 1 }
    if (line ~ /^[ \t]*}[ \t]*$/)     { delete current_domains; return 1 }

    # location 匹配（完美支持 = / ~ \.php$ ^~ "/path" '/path' 等所有写法）
    if (line ~ /^[ \t]*location[ \t]*[=~^ ]/) {
        if (match(line, /^[ \t]*location[ \t]*[=~^ ]*[ \t]*([^ {]+|".*"|'.*')/, m)) {
            path = normalize_path(m[1])

            # 同行的 proxy_pass
            if (match(line, /proxy_pass[ \t]+([^;}+]+)/, m)) {
                backend = process_proxy_pass(m[1])
                output(path, backend)
                return 1
            }

            # 跨行 proxy_pass
            saved_path = path
            while (getline > 0) {
                $0 = trim($0)
                if ($0 ~ /^[ \t]*}/) break
                if (substr($0,1,1) == "#") continue
                if ($0 ~ /proxy_pass[ \t]+/) {
                    sub(/.*proxy_pass[ \t]+/, "", $0)
                    gsub(/[;\r].*$/, "", $0)
                    backend = process_proxy_pass($0)
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
        printf "%-45s → %-35s → %s\n", d, p, b
    }
}
' | sort -u
