#!/usr/bin/env bash
# Clash Verge Rev share kit installer for macOS.
# Install Clash Verge Rev, import your own subscription, run it once, then quit it before running this script.
set -euo pipefail

CLASH_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
BACKUP_DIR="$CLASH_DIR/backup_$(date +%Y%m%d_%H%M%S)"
PACKAGE_VERSION="dev"

for version_file in "$SCRIPT_DIR/VERSION.txt" "$SCRIPT_DIR/../VERSION.txt"; do
    if [ -f "$version_file" ]; then
        PACKAGE_VERSION="$(tr -d '\r\n' < "$version_file")"
        break
    fi
done

cleanup_old_backups() {
    old_backups="$(find "$CLASH_DIR" -maxdepth 1 -type d -name 'backup_*' -print 2>/dev/null | sort -r | awk 'NR > 5')"
    if [ -n "$old_backups" ]; then
        echo "$old_backups" | while IFS= read -r old_backup; do
            rm -rf "$old_backup"
        done
        echo ">>> 已清理旧备份，仅保留最近 5 个 backup_* 目录"
    fi
}

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

echo ">>> 安装包版本: $PACKAGE_VERSION"
echo ">>> 安装来源: $SCRIPT_DIR"

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

cleanup_old_backups

echo ""
echo ">>> 安装完成。你的订阅和节点数据未被修改。"
echo ">>> 原文件已备份到: $BACKUP_DIR"
echo ">>> 配置文件已写入；重新打开 Clash Verge Rev 后即生效"
echo ">>> 安装后确认: 代理页能看到 US / Google / YouTube / Exchange"
echo ">>> 如果某类网站异常，先换对应策略组节点；如果规则集下载失败，请查看 Clash Verge Rev 日志"
echo ">>> 也可以按 README.txt 的“安装后 60 秒检查清单”逐项测试"
pause_before_close
