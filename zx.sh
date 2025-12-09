#!/bin/bash

# ===== 四个远程脚本地址 =====
URL0="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/bt.sh"
URL1="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/4zdh.sh"
URL2="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/zdh.sh"
URL3="https://raw.githubusercontent.com/AxiaoXe/js/refs/heads/main/ok.sh"

# 临时文件，用于 wget 时使用
TMPFILE=$(mktemp /tmp/remote_script.XXXXXX.sh)
trap 'rm -f "$TMPFILE" 2>/dev/null' EXIT

# ===== 执行单个远程脚本的函数 =====
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
        echo "[!] 错误：系统中既没有 curl 也没有 wget，无法继续！"
        exit 1
    fi

    if [ $ret -eq 0 ]; then
        echo " ✓ $name 执行成功"
    else
        echo " ✗ $name 执行失败（返回码 $ret），但继续执行下一个脚本"
    fi
    echo
}

# ===== 主流程 =====
echo "=================================================="
echo "    开始依次执行 4 个远程脚本（失败也会继续下一个）"
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
