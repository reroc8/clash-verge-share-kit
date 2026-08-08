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
ARCHIVE_TMP=""
cleanup() {
    rm -rf "$TMP_DIR"
    if [ -n "$ARCHIVE_TMP" ]; then
        rm -f "$ARCHIVE_TMP"
    fi
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1; then
    echo "错误: 未找到 Node.js，无法运行 Script.js 回归测试"
    exit 1
fi
node --check "$ROOT_DIR/config/Script.js"

MIHOMO_BIN="${MIHOMO_BIN:-}"
if [ -z "$MIHOMO_BIN" ] && command -v mihomo >/dev/null 2>&1; then
    MIHOMO_BIN="$(command -v mihomo)"
fi
if [ -z "$MIHOMO_BIN" ] && [ -x "/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" ]; then
    MIHOMO_BIN="/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo"
fi
if [ -n "$MIHOMO_BIN" ] && [ -x "$MIHOMO_BIN" ]; then
    MIHOMO_BIN="$MIHOMO_BIN" node "$ROOT_DIR/tests/test-script.js"
else
    node "$ROOT_DIR/tests/test-script.js"
    echo "警告: 未找到 Mihomo，已跳过真实内核配置验证"
fi

if command -v ruby >/dev/null 2>&1; then
    ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' \
        "$ROOT_DIR/config/Merge.yaml" \
        "$ROOT_DIR/config/verge.yaml" \
        "$ROOT_DIR/config/dns_config.yaml"
else
    echo "警告: 未找到 Ruby，已跳过 YAML 解析验证"
fi

bash -n "$ROOT_DIR/install/install-macos.command"
bash -n "$ROOT_DIR/macOS点我安装.command"
bash -n "$ROOT_DIR/scripts/check-sensitive.sh"
bash -n "$ROOT_DIR/tests/test-installers.sh"
bash "$ROOT_DIR/tests/test-installers.sh"

POWERSHELL_BIN=""
if command -v pwsh >/dev/null 2>&1; then
    POWERSHELL_BIN="$(command -v pwsh)"
elif command -v powershell >/dev/null 2>&1; then
    POWERSHELL_BIN="$(command -v powershell)"
fi
if [ -n "$POWERSHELL_BIN" ]; then
    for ps_file in "$ROOT_DIR/install/install-windows.ps1" "$ROOT_DIR/install/sync-profile-bound-files.ps1"; do
        "$POWERSHELL_BIN" -NoProfile -Command \
            '$tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tokens, [ref]$errors); if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }' \
            "$ps_file"
    done
    "$POWERSHELL_BIN" -NoProfile -File "$ROOT_DIR/tests/test-windows-sync.ps1"
else
    echo "警告: 未找到 pwsh，已跳过 Windows PowerShell 语法与同步测试"
fi

"$ROOT_DIR/scripts/check-sensitive.sh"

mkdir -p "$DIST_DIR"

cp "$ROOT_DIR/config/verge.yaml"       "$TMP_DIR/verge.yaml"
cp "$ROOT_DIR/config/dns_config.yaml"  "$TMP_DIR/dns_config.yaml"
cp "$ROOT_DIR/config/Merge.yaml"       "$TMP_DIR/Merge.yaml"
cp "$ROOT_DIR/config/Script.js"        "$TMP_DIR/Script.js"
cp "$ROOT_DIR/install/install-windows.bat"   "$TMP_DIR/Windows点我安装.bat"
cp "$ROOT_DIR/install/install-windows.ps1"   "$TMP_DIR/install-windows.ps1"
cp "$ROOT_DIR/install/install-macos.command" "$TMP_DIR/macOS点我安装.command"
cp "$ROOT_DIR/install/sync-profile-bound-files.ps1" "$TMP_DIR/sync-profile-bound-files.ps1"
BAT_NONASCII_LOG="$TMP_DIR/bat-nonascii.txt"
if LC_ALL=C grep -n '[^[:print:][:space:]]' "$ROOT_DIR/install/install-windows.bat" > "$BAT_NONASCII_LOG"; then
    echo "错误: install/install-windows.bat 必须保持纯 ASCII，避免 Windows cmd 编码解析失败"
    cat "$BAT_NONASCII_LOG"
    exit 1
fi
rm -f "$BAT_NONASCII_LOG"
INSTALL_PS1_NONASCII_LOG="$TMP_DIR/install-ps1-nonascii.txt"
if LC_ALL=C grep -n '[^[:print:][:space:]]' "$ROOT_DIR/install/install-windows.ps1" > "$INSTALL_PS1_NONASCII_LOG"; then
    echo "错误: install/install-windows.ps1 必须保持纯 ASCII，避免 Windows PowerShell 5.1 编码解析失败"
    cat "$INSTALL_PS1_NONASCII_LOG"
    exit 1
fi
rm -f "$INSTALL_PS1_NONASCII_LOG"
PS1_NONASCII_LOG="$TMP_DIR/ps1-nonascii.txt"
if LC_ALL=C grep -n '[^[:print:][:space:]]' "$ROOT_DIR/install/sync-profile-bound-files.ps1" > "$PS1_NONASCII_LOG"; then
    echo "错误: install/sync-profile-bound-files.ps1 必须保持纯 ASCII，避免 Windows PowerShell 5.1 编码解析失败"
    cat "$PS1_NONASCII_LOG"
    exit 1
fi
rm -f "$PS1_NONASCII_LOG"
perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/install-windows.ps1"
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

if ! grep -q "^## 安装" "$TMP_DIR/README.txt"; then
    echo "错误: README.md 缺少 Release 使用说明区段"
    exit 1
fi

perl -0pi -e 's/\r?\n/\r\n/g' "$TMP_DIR/Windows点我安装.bat"

if ! grep -q "install-windows.ps1" "$TMP_DIR/Windows点我安装.bat"; then
    echo "错误: Windows 安装入口必须只负责启动 install-windows.ps1"
    exit 1
fi
if ! grep -q "5a6J6KOF5a6M5oiQ44CC" "$TMP_DIR/install-windows.ps1"; then
    echo "错误: Windows PowerShell 安装脚本缺少中文完成提示的 Base64 文案"
    exit 1
fi
if grep -q "Package version:" "$TMP_DIR/Windows点我安装.bat"; then
    echo "错误: Windows 安装入口仍包含英文安装提示"
    exit 1
fi

"$ROOT_DIR/scripts/check-sensitive.sh" "$TMP_DIR"

cd "$TMP_DIR"
ARCHIVE_TMP="$(mktemp "$DIST_DIR/.${ZIP_NAME}.XXXXXX")"
python3 - "$ARCHIVE_TMP" <<'PY'
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
        archive_name = path.as_posix()
        info = zipfile.ZipInfo(archive_name)
        permission_bits = 0o755 if archive_name == "macOS点我安装.command" else 0o644
        info.date_time = time.localtime(path.stat().st_mtime)[:6]
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = ((0o100000 | permission_bits) & 0xFFFF) << 16
        archive.writestr(info, path.read_bytes())

with zipfile.ZipFile(dest) as archive:
    names = set(archive.namelist())
    required = {
        "Windows点我安装.bat",
        "install-windows.ps1",
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

    for item in archive.infolist():
        expected_mode = 0o755 if item.filename == "macOS点我安装.command" else 0o644
        actual_mode = (item.external_attr >> 16) & 0o777
        if actual_mode != expected_mode:
            raise SystemExit(f"{item.filename} mode is {oct(actual_mode)}, expected {oct(expected_mode)}")
PY

mv -f "$ARCHIVE_TMP" "$DIST_DIR/$ZIP_NAME"
ARCHIVE_TMP=""

if [ -n "$VERSION" ] && [ "${KEEP_OLD_ZIPS:-0}" != "1" ]; then
    find "$DIST_DIR" -type f -name 'clash-verge-share-kit-*.zip' ! -name "$ZIP_NAME" -delete
fi

echo "完成: $DIST_DIR/$ZIP_NAME"
