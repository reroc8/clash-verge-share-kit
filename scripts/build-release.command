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

{
    echo "Clash Verge Rev 小白稳定分享包"
    echo
    awk '
        /<!-- release-readme:start -->/ { emit = 1; next }
        /<!-- release-readme:pause -->/ { emit = 0; next }
        /<!-- release-readme:resume -->/ { emit = 1; next }
        /<!-- release-readme:end -->/ { emit = 0; next }
        emit { print }
    ' "$ROOT_DIR/README.md"
} > "$TMP_DIR/README.txt"

if ! grep -q "安装方式" "$TMP_DIR/README.txt"; then
    echo "错误: README.md 缺少 Release 使用说明区段"
    exit 1
fi

perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/install-windows.bat"

cd "$TMP_DIR"
zip -qr "$DIST_DIR/$ZIP_NAME" .

echo "完成: $DIST_DIR/$ZIP_NAME"
