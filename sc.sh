# 一条命令搞定，彻底清理所有脚本生成的 location（推荐直接执行）
grep -rlE 'location /.(help|news|page|blog|bangzhuzhongxin|zh|pc|support|info|about|pg|pgslot|slot|game|casino|live)/' /etc/nginx/sites-enabled/ | xargs -r sed -i '/location \//,/^\s*}/{
    /xzz\.pier46\.com\|ide\.hashbank8\.com\|index\.php?domain=/d
    /^\s*}$/d
    /^[\t ]*$/d
}'

# 再顺手把可能残留的空行和多余大括号删干净
grep -rlE 'location|server_name' /etc/nginx/sites-enabled/ | xargs -r sed -i '/^{$/,/^}$/d; /^}$/d; /^[[:space:]]*$/d'

# 最后校验并重载
nginx -t && systemctl reload nginx && echo "所有隐蔽路径已彻底删除干净！"
