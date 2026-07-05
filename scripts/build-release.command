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
    CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
    if [ ! -f "$CHANGELOG_FILE" ]; then
        echo "错误: 缺少 CHANGELOG.md"
        exit 1
    fi
    if ! awk -v version="$VERSION" '
        $0 == "## " version { found = 1; next }
        found && /^## / { exit }
        found && /^- / { item = 1 }
        END { exit !(found && item) }
    ' "$CHANGELOG_FILE"; then
        echo "错误: CHANGELOG.md 缺少 $VERSION 标题，或该版本下没有变更条目"
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
cp "$ROOT_DIR/install/install-windows.bat"   "$TMP_DIR/Windows点我安装.bat"
cp "$ROOT_DIR/install/install-macos.command" "$TMP_DIR/macOS点我安装.command"
cp "$ROOT_DIR/install/sync-profile-bound-files.ps1" "$TMP_DIR/sync-profile-bound-files.ps1"
PS1_NONASCII_LOG="$TMP_DIR/ps1-nonascii.txt"
if LC_ALL=C grep -n '[^[:print:][:space:]]' "$ROOT_DIR/install/sync-profile-bound-files.ps1" > "$PS1_NONASCII_LOG"; then
    echo "错误: install/sync-profile-bound-files.ps1 必须保持纯 ASCII，避免 Windows PowerShell 5.1 编码解析失败"
    cat "$PS1_NONASCII_LOG"
    exit 1
fi
rm -f "$PS1_NONASCII_LOG"
perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/sync-profile-bound-files.ps1"
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

if [ -f "$ROOT_DIR/CHANGELOG.md" ]; then
    cp "$ROOT_DIR/CHANGELOG.md" "$TMP_DIR/CHANGELOG.txt"
fi

if ! grep -q "安装方式" "$TMP_DIR/README.txt"; then
    echo "错误: README.md 缺少 Release 使用说明区段"
    exit 1
fi

perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/Windows点我安装.bat"

rm -f "$DIST_DIR/$ZIP_NAME"

cd "$TMP_DIR"
python3 - "$DIST_DIR/$ZIP_NAME" <<'PY'
from pathlib import Path
import sys
import time
import zipfile

dest = Path(sys.argv[1])
root = Path(".")

with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if not path.is_file():
            continue
        info = zipfile.ZipInfo(path.as_posix())
        mode = path.stat().st_mode
        info.date_time = time.localtime(path.stat().st_mtime)[:6]
        info.external_attr = (mode & 0xFFFF) << 16
        archive.writestr(info, path.read_bytes())

with zipfile.ZipFile(dest) as archive:
    names = set(archive.namelist())
    required = {
        "Windows点我安装.bat",
        "macOS点我安装.command",
        "sync-profile-bound-files.ps1",
        "README.txt",
        "VERSION.txt",
    }
    missing = sorted(required - names)
    if missing:
        raise SystemExit("missing release files: " + ", ".join(missing))

    for name in ["Windows点我安装.bat", "macOS点我安装.command"]:
        cn_info = archive.getinfo(name)
        if not (cn_info.flag_bits & 0x800):
            raise SystemExit(f"{name} is not marked as UTF-8 in zip")
PY

if [ -n "$VERSION" ] && [ "${KEEP_OLD_ZIPS:-0}" != "1" ]; then
    find "$DIST_DIR" -type f -name 'clash-verge-share-kit-*.zip' ! -name "$ZIP_NAME" -delete
fi

echo "完成: $DIST_DIR/$ZIP_NAME"
