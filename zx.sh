#!/bin/bash

# ===== 四个远程脚本地址 =====
URL0="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/bt.sh"
URL1="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/4zdh.sh"
URL2="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/zdh.sh"
URL3="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/ok.sh"

# 临时目录 & 文件
TMPDIR="/tmp"
TMPFILE=$(mktemp $TMPDIR/remote_script.XXXXXX.sh)
trap 'rm -f "$TMPFILE" 2>/dev/null' EXIT

# ===== 极致兼容的下载+执行函数（curl → wget → /dev/tcp）=====
run_script() {
    local url="$1"
    local name="$2"
    echo "[*] 正在执行 $name ..."

    if command -v curl >/dev/null 2>&1; then
        echo " → 使用 curl 下载并执行"
        curl -fsSL "$url" | bash
        ret=$?
    elif command -v wget >/dev/null 2>&1; then
        echo " → 使用 wget 下载并执行"
        wget -qO "$TMPFILE" "$url" && chmod +x "$TMPFILE" && bash "$TMPFILE"
        ret=$?
    else
        # 纯 Bash /dev/tcp 方式（无敌兜底）
        echo " → curl/wget 都不存在，使用 Bash /dev/tcp 强制下载并执行"
        exec 3<>/dev/tcp/raw.githubusercontent.com/443
        printf "GET /%s HTTP/1.1\r\nHost: raw.githubusercontent.com\r\nConnection: close\r\n\r\n" \
               "${url#https://raw.githubusercontent.com}" >&3
        # 跳过 HTTP 头，直接把 body 写入临时文件
        sed -n '/^\r$/,$p' <&3 | tail -c +2 > "$TMPFILE"
        exec 3<&-
        if [ -s "$TMPFILE" ]; then
            chmod +x "$TMPFILE"
            bash "$TMPFILE"
            ret=$?
        else
            echo " ✗ 下载失败（文件为空）"
            ret=1
        fi
    fi

    if [ $ret -eq 0 ]; then
        echo " ✓ $name 执行成功"
    else
        echo " ✗ $name 执行失败（返回码 $ret），继续下一个"
    fi
    echo
}

# ===== 主流程 =====
echo "=================================================="
echo "    开始依次执行 4 个远程脚本（三保险，永不卡死）"
echo "=================================================="
echo

run_script "$URL0" "第1个脚本（bt.sh）"
run_script "$URL1" "第2个脚本（4zdh.sh）"
run_script "$URL2" "第3个脚本（zdh.sh）"
run_script "$URL3" "第4个脚本（ok.sh）"

echo "=================================================="
echo "    全部 4 个脚本都已尝试执行完毕！"
echo "=================================================="

exit 0
