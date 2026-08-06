#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/clash-installer-test.XXXXXX")"
trap 'rm -rf "$TMP_HOME"' EXIT

grep -Fq '%SCRIPT_DIR%install\install-windows.ps1' "$ROOT_DIR/install/install-windows.bat"
if grep -Fq '%SCRIPT_DIR%..\install\install-windows.ps1' "$ROOT_DIR/install/install-windows.bat"; then
    echo "Windows BAT still contains the invalid parent-directory fallback"
    exit 1
fi
if grep -Eq '& powershell .*\| Out-Null' "$ROOT_DIR/install/install-windows.ps1"; then
    echo "Windows installer still reads LASTEXITCODE after a pipeline"
    exit 1
fi
grep -Fq '$syncExitCode = $LASTEXITCODE' "$ROOT_DIR/install/install-windows.ps1"
grep -Fq '[Console]::add_CancelKeyPress' "$ROOT_DIR/install/install-windows.ps1"
grep -Fq '.installer-backup' "$ROOT_DIR/install/install-macos.command"
grep -Fq '.installer-backup' "$ROOT_DIR/install/install-windows.ps1"

CLASH_DIR="$TMP_HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
PROFILES_DIR="$CLASH_DIR/profiles"
mkdir -p "$PROFILES_DIR" "$TMP_HOME/bin"

printf '%s\n' '#!/usr/bin/env sh' 'exit 1' > "$TMP_HOME/bin/pgrep"
chmod +x "$TMP_HOME/bin/pgrep"

printf '%s\n' 'old root verge' > "$CLASH_DIR/verge.yaml"
printf '%s\n' 'old root dns' > "$CLASH_DIR/dns_config.yaml"
printf '%s\n' 'old default merge' > "$PROFILES_DIR/Merge.yaml"
printf '%s\n' 'old default script' > "$PROFILES_DIR/Script.js"
printf '%s\n' 'old profile verge' > "$PROFILES_DIR/verge.yaml"
printf '%s\n' 'old order first' > "$PROFILES_DIR/order-first.yaml"
printf '%s\n' 'old inline' > "$PROFILES_DIR/inline.js"
printf '%s\n' 'old quoted' > "$PROFILES_DIR/quoted.yaml"
printf '%s\n' 'old hash file' > "$PROFILES_DIR/a#b.yaml"
printf '%s\n' 'keep me' > "$PROFILES_DIR/untouched.yaml"

# UTF-8 BOM 开头验证首行解析；file 值内带 # 验证引号优先剥离
printf '\xEF\xBB\xBF%s\n' 'items:' > "$CLASH_DIR/profiles.yaml"
printf '%s\n' \
    '- uid: collision' \
    '  type: merge' \
    '  file: verge.yaml' \
    '- uid: order-first' \
    '  file: order-first.yaml' \
    '  type: merge' \
    '- {uid: inline, file: inline.js, type: script}' \
    '- uid: quoted' \
    '  type: "merge" # valid quoted scalar' \
    '  file: "quoted.yaml" # valid inline comment' \
    '- uid: hashname' \
    '  type: merge' \
    '  file: "a#b.yaml" # inline comment' \
    '- uid: normal' \
    '  file: untouched.yaml' \
    '  type: remote' \
    >> "$CLASH_DIR/profiles.yaml"

INSTALL_LOG="$TMP_HOME/install.log"
PATH="$TMP_HOME/bin:$PATH" HOME="$TMP_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$INSTALL_LOG" 2>&1

cmp -s "$ROOT_DIR/config/Merge.yaml" "$PROFILES_DIR/verge.yaml"
cmp -s "$ROOT_DIR/config/Merge.yaml" "$PROFILES_DIR/order-first.yaml"
grep -Fqx 'old inline' "$PROFILES_DIR/inline.js"
cmp -s "$ROOT_DIR/config/Merge.yaml" "$PROFILES_DIR/quoted.yaml"
cmp -s "$ROOT_DIR/config/Merge.yaml" "$PROFILES_DIR/a#b.yaml"
grep -Fqx 'keep me' "$PROFILES_DIR/untouched.yaml"
grep -Fq '仅支持 Clash Verge 生成的 - uid: 结构' "$INSTALL_LOG"

BACKUP_DIR="$(find "$CLASH_DIR" -maxdepth 1 -type d -name 'backup_*' | head -n 1)"
test -n "$BACKUP_DIR"
grep -Fqx 'old root verge' "$BACKUP_DIR/root/verge.yaml"
grep -Fqx 'old profile verge' "$BACKUP_DIR/profiles/verge.yaml"
grep -Fqx 'old order first' "$BACKUP_DIR/profiles/order-first.yaml"

# --- restore path: a midway failure must roll files back from the backup ---
RESTORE_HOME="$TMP_HOME/restore"
KIT_DIR="$RESTORE_HOME/kit"
CLASH2_DIR="$RESTORE_HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
mkdir -p "$KIT_DIR/install" "$KIT_DIR/config" "$CLASH2_DIR/profiles"
cp "$ROOT_DIR/install/install-macos.command" "$KIT_DIR/install/"
cp "$ROOT_DIR/config/Merge.yaml" "$ROOT_DIR/config/Script.js" \
    "$ROOT_DIR/config/verge.yaml" "$ROOT_DIR/config/dns_config.yaml" "$KIT_DIR/config/"
# Make one config source unreadable so the copy step fails after backups are taken.
chmod 000 "$KIT_DIR/config/Script.js"

printf '%s\n' 'old root verge' > "$CLASH2_DIR/verge.yaml"
printf '%s\n' 'old root dns' > "$CLASH2_DIR/dns_config.yaml"
printf '%s\n' 'old default merge' > "$CLASH2_DIR/profiles/Merge.yaml"
printf '%s\n' 'old default script' > "$CLASH2_DIR/profiles/Script.js"
# 绑定一个安装前不存在的 merge 文件，验证 created-files 回滚删除
printf '%s\n' \
    'items:' \
    '- uid: newbind' \
    '  type: merge' \
    '  file: new-merge.yaml' \
    > "$CLASH2_DIR/profiles.yaml"

RESTORE_LOG="$RESTORE_HOME/restore.log"
PATH="$TMP_HOME/bin:$PATH" HOME="$RESTORE_HOME" bash "$KIT_DIR/install/install-macos.command" > "$RESTORE_LOG" 2>&1 && {
    echo "restore test: installer unexpectedly succeeded"
    exit 1
}
chmod 644 "$KIT_DIR/config/Script.js"

grep -Fq '正在尝试恢复安装前配置' "$RESTORE_LOG"
grep -Fq '已尝试恢复' "$RESTORE_LOG"
grep -Fqx 'old default merge' "$CLASH2_DIR/profiles/Merge.yaml"
grep -Fqx 'old default script' "$CLASH2_DIR/profiles/Script.js"
grep -Fqx 'old root verge' "$CLASH2_DIR/verge.yaml"
grep -Fqx 'old root dns' "$CLASH2_DIR/dns_config.yaml"
test ! -f "$CLASH2_DIR/profiles/new-merge.yaml" && echo "created file removed on rollback"

# --- backup cleanup: keep newest 5 auto backups, keep manual backups ---
CLEAN_HOME="$TMP_HOME/clean"
CLASH3_DIR="$CLEAN_HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
mkdir -p "$CLASH3_DIR/profiles"
printf '%s\n' 'old root verge' > "$CLASH3_DIR/verge.yaml"
printf '%s\n' 'old root dns' > "$CLASH3_DIR/dns_config.yaml"
printf '%s\n' 'old default merge' > "$CLASH3_DIR/profiles/Merge.yaml"
printf '%s\n' 'old default script' > "$CLASH3_DIR/profiles/Script.js"
# 6 个带安装器标记的旧自动备份 + 1 个手工备份 + 1 个碰巧同名的无标记目录；
# 安装会新增 1 个带标记的自动备份 → 清理后带标记的应剩 5 个，手工与碰巧同名目录保留
for i in 1 2 3 4 5 6; do
    mkdir -p "$CLASH3_DIR/backup_20260101_00000${i}_AAAAAA"
    touch "$CLASH3_DIR/backup_20260101_00000${i}_AAAAAA/.installer-backup"
done
mkdir -p "$CLASH3_DIR/backup_20260101_000000_manual_keep"
touch "$CLASH3_DIR/backup_20260101_000000_manual_keep/keep.txt"
mkdir -p "$CLASH3_DIR/backup_20260101_000000_AAAAAA"
touch "$CLASH3_DIR/backup_20260101_000000_AAAAAA/keep.txt"

CLEAN_LOG="$CLEAN_HOME/clean.log"
PATH="$TMP_HOME/bin:$PATH" HOME="$CLEAN_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$CLEAN_LOG" 2>&1

MARKED_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*' -exec test -f '{}/.installer-backup' \; -print | wc -l | tr -d ' ')"
MANUAL_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*_manual_*' | wc -l | tr -d ' ')"
COLLISION_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_20260101_000000_AAAAAA' | wc -l | tr -d ' ')"
TOTAL_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*' | wc -l | tr -d ' ')"
test "$MARKED_COUNT" -eq 5 || { echo "expected 5 marked auto backups, got $MARKED_COUNT"; exit 1; }
test "$MANUAL_COUNT" -eq 1 || { echo "expected 1 manual backup to survive, got $MANUAL_COUNT"; exit 1; }
test "$COLLISION_COUNT" -eq 1 || { echo "expected colliding unmarked directory to survive"; exit 1; }
test "$TOTAL_COUNT" -eq 7 || { echo "expected 7 backup dirs total, got $TOTAL_COUNT"; exit 1; }

echo "Installer regression tests passed"
