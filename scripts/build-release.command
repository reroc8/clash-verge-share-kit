#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ROOT_VERSION_FILE="$ROOT_DIR/VERSION.txt"
VERSION="${1:-}"
VERSION_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
if [ -n "$VERSION" ]; then
    if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
        echo "错误: 版本号必须使用 vX.Y.Z 格式，例如 v0.3.8"
        exit 1
    fi
    if [ ! -f "$ROOT_VERSION_FILE" ]; then
        echo "错误: 缺少 VERSION.txt。请先在项目根目录写入目标版本号"
        exit 1
    fi
    PACKAGE_VERSION="$(tr -d '\r\n' < "$ROOT_VERSION_FILE")"
    if ! [[ "$PACKAGE_VERSION" =~ $VERSION_RE ]]; then
        echo "错误: VERSION.txt 内容必须使用 vX.Y.Z 格式"
        exit 1
    fi
    if [ "$VERSION" != "$PACKAGE_VERSION" ]; then
        echo "错误: 参数版本 $VERSION 与 VERSION.txt $PACKAGE_VERSION 不一致"
        echo "请先确认要发布的版本，只保留一个版本来源"
        exit 1
    fi
    ZIP_NAME="clash-verge-share-kit-${VERSION}.zip"
else
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    PACKAGE_VERSION="dev-$TIMESTAMP"
    ZIP_NAME="clash-verge-share-kit-${PACKAGE_VERSION}.zip"
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
echo "$PACKAGE_VERSION" > "$TMP_DIR/VERSION.txt"

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

rm -f "$DIST_DIR/$ZIP_NAME"

cd "$TMP_DIR"
zip -qr "$DIST_DIR/$ZIP_NAME" .

if [ -n "$VERSION" ] && [ "${KEEP_OLD_ZIPS:-0}" != "1" ]; then
    find "$DIST_DIR" -type f -name 'clash-verge-share-kit-*.zip' ! -name "$ZIP_NAME" -delete
fi

echo "完成: $DIST_DIR/$ZIP_NAME"
