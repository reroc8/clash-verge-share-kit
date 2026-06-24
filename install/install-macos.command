#!/usr/bin/env bash
# Clash Verge Rev share kit installer for macOS.
# Install Clash Verge Rev, import your own subscription, run it once, then quit it before running this script.
set -euo pipefail

CLASH_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
BACKUP_DIR="$CLASH_DIR/backup_$(date +%Y%m%d_%H%M%S)"
REQUIRED_GROUPS=(Proxies US Google YouTube Telegram)

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

if pgrep -f "Clash Verge" >/dev/null 2>&1 || pgrep -f "verge-mihomo" >/dev/null 2>&1; then
    echo "错误: 检测到 Clash Verge Rev 正在运行，请先完全退出"
    exit 1
fi

mkdir -p "$CLASH_DIR/profiles"

MISSING_GROUPS=()
for group in "${REQUIRED_GROUPS[@]}"; do
    if ! grep -R -- "- name: $group" "$CLASH_DIR/profiles" "$CLASH_DIR/clash-verge.yaml" >/dev/null 2>&1; then
        MISSING_GROUPS+=("$group")
    fi
done

if [ "${#MISSING_GROUPS[@]}" -gt 0 ]; then
    echo "错误: 你的订阅看起来缺少这些策略组:"
    echo "    ${MISSING_GROUPS[*]}"
    echo ""
    echo "这个配置适合同结构订阅。请先导入自己的订阅，并确认策略组里有:"
    echo "    Proxies / US / Google / YouTube / Telegram"
    echo ""
    echo "为避免装完不可用，已停止安装。"
    exit 1
fi

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
echo ">>> 建议选择: US=稳定美国节点，Google/YouTube=常用地区节点，Exchange=账号允许地区节点"
