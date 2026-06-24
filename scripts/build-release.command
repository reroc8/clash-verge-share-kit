#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ZIP_NAME="clash-verge-share-kit-${TIMESTAMP}.zip"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

"$ROOT_DIR/scripts/check-sensitive.sh"

mkdir -p "$DIST_DIR"

cp "$ROOT_DIR/config/verge.yaml"       "$TMP_DIR/verge.yaml"
cp "$ROOT_DIR/config/dns_config.yaml"  "$TMP_DIR/dns_config.yaml"
cp "$ROOT_DIR/config/Merge.yaml"       "$TMP_DIR/Merge.yaml"
cp "$ROOT_DIR/config/Script.js"        "$TMP_DIR/Script.js"
cp "$ROOT_DIR/install/install-macos.command" "$TMP_DIR/install-macos.command"
cp "$ROOT_DIR/install/install-windows.bat"   "$TMP_DIR/install-windows.bat"

cat > "$TMP_DIR/README.txt" << 'EOF'
Clash Verge Rev 小白稳定分享包

这个包包含：
- 分流规则
- DNS 配置
- Clash Verge Rev 基础 App 设置

这个包不包含：
- 分享者的订阅
- 分享者的节点
- 分享者的账号密码

使用前：
1. 先安装 Clash Verge Rev。
2. 导入你自己的订阅。
3. 打开并确认能正常代理。
4. 完全退出 Clash Verge Rev。

安装：
- macOS：双击 install-macos.command。
- Windows 10/11：双击 install-windows.bat。

注意：
- 你的订阅里需要有 Proxies / US / Google / YouTube / Telegram 这些策略组。
- Exchange 交易所组会由脚本自动生成，使用时请选择账号允许地区节点。
- 安装脚本会先备份原文件，再覆盖分流规则、DNS 和基础设置。
- 你的订阅和节点不会被修改。
EOF

perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/install-windows.bat"

cd "$TMP_DIR"
zip -qr "$DIST_DIR/$ZIP_NAME" .

echo "完成: $DIST_DIR/$ZIP_NAME"
