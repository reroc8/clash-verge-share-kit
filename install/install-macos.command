#!/usr/bin/env bash
# Clash Verge Rev share kit installer for macOS.
# Install Clash Verge Rev, import your own subscription, run it once, then quit it before running this script.
set -euo pipefail

CLASH_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
BACKUP_DIR="$CLASH_DIR/backup_$(date +%Y%m%d_%H%M%S)"

pause_before_close() {
    [ -t 0 ] || return 0
    echo ""
    read -r -p "按回车键关闭窗口..." _ || true
}

on_exit() {
    code="$1"
    if [ "$code" -ne 0 ]; then
        echo ""
        echo "安装未完成，请检查上面的错误信息。"
        pause_before_close
    fi
}

trap 'on_exit $?' EXIT

if [ ! -f "$CONFIG_DIR/Merge.yaml" ]; then
    CONFIG_DIR="$SCRIPT_DIR"
fi

if [ ! -f "$CONFIG_DIR/Merge.yaml" ]; then
    echo "错误: 未找到配置文件。请确认 config/ 目录存在，或使用 Release zip 根目录运行。"
    exit 1
fi

if [ ! -d "$CLASH_DIR" ]; then
    echo "错误: 未找到 Clash Verge Rev 数据目录"
    echo "请先安装 Clash Verge Rev，导入自己的订阅，并运行一次"
    exit 1
fi

is_clash_running() {
    pgrep -x "clash-verge" >/dev/null 2>&1 ||
    pgrep -x "verge-mihomo" >/dev/null 2>&1 ||
    pgrep -x "verge-mihomo-alpha" >/dev/null 2>&1 ||
    pgrep -x "mihomo" >/dev/null 2>&1
}

if is_clash_running; then
    echo "错误: 检测到 Clash Verge Rev 正在运行，请先完全退出"
    exit 1
fi

mkdir -p "$CLASH_DIR/profiles"

mkdir -p "$BACKUP_DIR"

echo ">>> 安装前备份到: $BACKUP_DIR"

for file in "Merge.yaml" "Script.js" "verge.yaml" "dns_config.yaml"; do
    if [ "$file" = "Merge.yaml" ] || [ "$file" = "Script.js" ]; then
        [ -f "$CLASH_DIR/profiles/$file" ] && cp "$CLASH_DIR/profiles/$file" "$BACKUP_DIR/$file" 2>/dev/null
    else
        [ -f "$CLASH_DIR/$file" ] && cp "$CLASH_DIR/$file" "$BACKUP_DIR/$file" 2>/dev/null
    fi
done

echo ">>> 正在安装..."
cp "$CONFIG_DIR/Merge.yaml"       "$CLASH_DIR/profiles/Merge.yaml"
cp "$CONFIG_DIR/Script.js"        "$CLASH_DIR/profiles/Script.js"
cp "$CONFIG_DIR/verge.yaml"       "$CLASH_DIR/verge.yaml"
cp "$CONFIG_DIR/dns_config.yaml"  "$CLASH_DIR/dns_config.yaml"

echo ""
echo ">>> 安装完成。你的订阅和节点数据未被修改。"
echo ">>> 原文件已备份到: $BACKUP_DIR"
echo ">>> 请重新打开 Clash Verge Rev"
echo ">>> 脚本会自动补齐常见策略组。打开后可按需选择: US / Google / YouTube / Exchange"
pause_before_close
