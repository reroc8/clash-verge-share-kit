#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="${1:-}"
if [ -n "$VERSION" ]; then
    ZIP_NAME="clash-verge-share-kit-${VERSION}.zip"
else
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    ZIP_NAME="clash-verge-share-kit-${TIMESTAMP}.zip"
fi
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

适合谁：
- 已经有自己的订阅，但只会导入，不知道怎么调。
- 希望 AI、Google、YouTube、Telegram、交易所和国内网站各走各的。
- 不想研究规则、策略组、DNS、TUN，只想下载、解压、双击安装。

不适合谁：
- 还没有任何 Clash Verge Rev 订阅的人。
- 想拿到作者节点、订阅、账号或 token 的人。
- 想绕过交易所、AI、流媒体平台地区限制的人。

它做什么：
- Claude / ChatGPT / Gemini 尽量走适合 AI 的线路。
- Google / Gmail / Google 登录走 Google 专用线路。
- YouTube 走 YouTube 专用线路。
- OKX / Bybit / Binance 走交易所专用线路。
- 国内网站、局域网、钉钉尽量直连。

使用前：
1. 先安装 Clash Verge Rev。
2. 导入你自己的订阅。
3. 打开并确认能正常代理。
4. 完全退出 Clash Verge Rev。

安装：
- macOS：双击 install-macos.command。
- Windows 10/11：双击 install-windows.bat。

注意：
- 脚本会尽量自动识别常见订阅结构，并补齐 Proxies / US / Google / YouTube / Telegram / Exchange。
- 如果识别不到地区节点，会降级到 Proxies 或 DIRECT，优先保证配置能启动。
- Exchange 交易所组会由脚本自动生成，使用时请选择账号允许地区节点。
- 安装脚本会先备份原文件，再覆盖分流规则、DNS 和基础设置。
- 你的订阅和节点不会被修改。

可以让自己的 AI Agent 帮你安装：
请让它不要上传、复制、泄露你的订阅链接、节点、token 或账号信息；
然后让它解压本包，按系统运行 install-macos.command 或 install-windows.bat。
EOF

perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/install-windows.bat"

cd "$TMP_DIR"
zip -qr "$DIST_DIR/$ZIP_NAME" .

echo "完成: $DIST_DIR/$ZIP_NAME"
