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

# 假 pkill：记录每次调用，并按 FAKE_PKILL_STATE 决定是否"让进程消失"（模拟清退成功）。
# 每个场景的 bin 目录都必须放一个：安装器在检测到进程时会真的执行 pkill，
# PATH 里没有替身就会命中开发者正在用的 Clash —— 踩过，反向验证时误杀了本机 GUI。
FAKE_PKILL_LOG="$TMP_HOME/pkill-calls.txt"
: > "$FAKE_PKILL_LOG"
export FAKE_PKILL_LOG
write_fake_pkill() {
    mkdir -p "$1"
    {
        echo '#!/usr/bin/env sh'
        echo 'printf "%s\n" "$*" >> "${FAKE_PKILL_LOG:-/dev/null}"'
        echo 'if [ -n "${FAKE_PKILL_STATE:-}" ]; then rm -f "$FAKE_PKILL_STATE"; fi'
        echo 'exit 0'
    } > "$1/pkill"
    chmod +x "$1/pkill"
}
write_fake_pkill "$TMP_HOME/bin"

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
# stdin 必须显式重定向：否则安装器继承调用方的终端，完成提示里的 read 会阻塞等待回车，
# 而所有输出都在日志文件里，表现为测试静默挂死（发版脚本调用本测试时同样受影响）。
PATH="$TMP_HOME/bin:$PATH" HOME="$TMP_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$INSTALL_LOG" 2>&1 < /dev/null

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
PATH="$TMP_HOME/bin:$PATH" HOME="$RESTORE_HOME" bash "$KIT_DIR/install/install-macos.command" > "$RESTORE_LOG" 2>&1 < /dev/null && {
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
PATH="$TMP_HOME/bin:$PATH" HOME="$CLEAN_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$CLEAN_LOG" 2>&1 < /dev/null

# 用 sh -c 传路径，避免依赖 find 对参数内嵌 {} 的替换：
# BSD find 支持内嵌替换，但 toybox/busybox 等实现不替换，会让这里恒为 0 而假失败。
MARKED_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*' -exec sh -c 'test -f "$1/.installer-backup"' _ {} \; -print | wc -l | tr -d ' ')"
MANUAL_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*_manual_*' | wc -l | tr -d ' ')"
COLLISION_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_20260101_000000_AAAAAA' | wc -l | tr -d ' ')"
TOTAL_COUNT="$(find "$CLASH3_DIR" -maxdepth 1 -type d -name 'backup_*' | wc -l | tr -d ' ')"
test "$MARKED_COUNT" -eq 5 || { echo "expected 5 marked auto backups, got $MARKED_COUNT"; exit 1; }
test "$MANUAL_COUNT" -eq 1 || { echo "expected 1 manual backup to survive, got $MANUAL_COUNT"; exit 1; }
test "$COLLISION_COUNT" -eq 1 || { echo "expected colliding unmarked directory to survive"; exit 1; }
test "$TOTAL_COUNT" -eq 7 || { echo "expected 7 backup dirs total, got $TOTAL_COUNT"; exit 1; }

# 前三段场景里没有任何进程被报告为在运行，安装器就不该调用 pkill
if [ -s "$FAKE_PKILL_LOG" ]; then
    echo "pkill must not be called when nothing is reported as running"
    cat "$FAKE_PKILL_LOG"
    exit 1
fi

# --- running-process detection and cleanup ---
# 造一套最小环境：数据目录存在、四个目标文件都是旧内容
make_running_env() {
    env_home="$1"
    env_clash="$env_home/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
    mkdir -p "$env_clash/profiles" "$env_home/bin"
    printf '%s\n' 'old root verge' > "$env_clash/verge.yaml"
    printf '%s\n' 'old root dns' > "$env_clash/dns_config.yaml"
    printf '%s\n' 'old default merge' > "$env_clash/profiles/Merge.yaml"
    printf '%s\n' 'old default script' > "$env_clash/profiles/Script.js"
}

# 场景 1：只有 root 的常驻服务 clash-verge-service 在跑。
# 这是本次修复的核心回归点——旧版用宽松的 `pgrep -i "clash-verge"`（不带 -u）会命中
# 这个 launchd 常驻进程，于是"用户已经退出 Clash 却仍被判定为在运行"。
# 假 pgrep 如实模拟真实语义：宽松查询命中服务，带 -u <自己> 的 GUI 查询与内核查询都不命中。
RUN1_HOME="$TMP_HOME/running1"
make_running_env "$RUN1_HOME"
cat > "$RUN1_HOME/bin/pgrep" <<'FAKE'
#!/usr/bin/env sh
case "$*" in
  *"-u "*) exit 1 ;;
  *clash-verge*) echo 999; exit 0 ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$RUN1_HOME/bin/pgrep"
write_fake_pkill "$RUN1_HOME/bin"
RUN1_LOG="$RUN1_HOME/install.log"
RUN1_PKILL_BEFORE="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if ! PATH="$RUN1_HOME/bin:$PATH" HOME="$RUN1_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$RUN1_LOG" 2>&1 < /dev/null; then
    echo "service-only: installer must proceed when only the root helper service runs"
    cat "$RUN1_LOG"
    exit 1
fi
if grep -Fq '正在尝试清退' "$RUN1_LOG"; then
    echo "service-only: installer must not try to kill anything"
    cat "$RUN1_LOG"
    exit 1
fi
RUN1_PKILL_AFTER="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if [ "$RUN1_PKILL_BEFORE" != "$RUN1_PKILL_AFTER" ]; then
    echo "service-only: installer must not call pkill for the root helper service"
    exit 1
fi
echo "service-only (root helper): installer proceeds"

# 场景 2：GUI 在跑，但能被清退 —— 安装器应自动清退后继续
RUN2_HOME="$TMP_HOME/running2"
make_running_env "$RUN2_HOME"
RUN2_STATE="$RUN2_HOME/clash-gui-running"
: > "$RUN2_STATE"
cat > "$RUN2_HOME/bin/pgrep" <<FAKE
#!/usr/bin/env sh
if [ -f "$RUN2_STATE" ]; then
    case "\$*" in
        *"-u "*) echo 4242; exit 0 ;;
    esac
fi
exit 1
FAKE
cat > "$RUN2_HOME/bin/pkill" <<FAKE
#!/usr/bin/env sh
printf "%s\n" "\$*" >> "\${FAKE_PKILL_LOG:-/dev/null}"
rm -f "$RUN2_STATE"
exit 0
FAKE
chmod +x "$RUN2_HOME/bin/pgrep" "$RUN2_HOME/bin/pkill"
RUN2_LOG="$RUN2_HOME/install.log"
RUN2_PKILL_BEFORE="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if ! PATH="$RUN2_HOME/bin:$PATH" HOME="$RUN2_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$RUN2_LOG" 2>&1 < /dev/null; then
    echo "auto-quit: installer must finish after stopping the running GUI"
    cat "$RUN2_LOG"
    exit 1
fi
grep -Fq '正在尝试清退' "$RUN2_LOG" || { echo "auto-quit: installer must attempt to stop the running GUI"; cat "$RUN2_LOG"; exit 1; }
RUN2_PKILL_AFTER="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if [ "$RUN2_PKILL_BEFORE" = "$RUN2_PKILL_AFTER" ]; then
    echo "auto-quit: installer must call pkill to stop the running GUI"
    exit 1
fi
echo "auto-quit (GUI stoppable): installer stops it and continues"

# 场景 3：GUI 清退失败 —— 安装器必须中止，且不得改动任何文件
RUN3_HOME="$TMP_HOME/running3"
make_running_env "$RUN3_HOME"
cat > "$RUN3_HOME/bin/pgrep" <<'FAKE'
#!/usr/bin/env sh
case "$*" in
  *"-u "*) echo 4242; exit 0 ;;
  *) exit 1 ;;
esac
FAKE
cat > "$RUN3_HOME/bin/pkill" <<'FAKE'
#!/usr/bin/env sh
printf "%s\n" "$*" >> "${FAKE_PKILL_LOG:-/dev/null}"
exit 0
FAKE
chmod +x "$RUN3_HOME/bin/pgrep" "$RUN3_HOME/bin/pkill"
RUN3_LOG="$RUN3_HOME/install.log"
RUN3_PKILL_BEFORE="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if PATH="$RUN3_HOME/bin:$PATH" HOME="$RUN3_HOME" bash "$ROOT_DIR/install/install-macos.command" > "$RUN3_LOG" 2>&1 < /dev/null; then
    echo "auto-quit failure: installer must abort when the GUI survives"
    exit 1
fi
grep -Fq '无法自动清退' "$RUN3_LOG" || { echo "auto-quit failure: expected an actionable message"; cat "$RUN3_LOG"; exit 1; }
RUN3_PKILL_AFTER="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if [ "$RUN3_PKILL_BEFORE" = "$RUN3_PKILL_AFTER" ]; then
    echo "auto-quit failure: installer must have tried pkill"
    exit 1
fi
RUN3_CLASH="$RUN3_HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
grep -Fqx 'old default merge' "$RUN3_CLASH/profiles/Merge.yaml" || { echo "auto-quit failure: installer must not touch files"; exit 1; }
test -z "$(find "$RUN3_CLASH" -maxdepth 1 -type d -name 'backup_*' -print)" || { echo "auto-quit failure: no backup must be taken"; exit 1; }
echo "auto-quit failure (GUI survives): installer aborts without touching files"

# --- 独立的「关闭 Clash」脚本 ---
CLOSE_SCRIPT="$ROOT_DIR/install/close-clash-macos.command"

# 4a. 什么都没跑：应当直接退出 0，且不调用 pkill
CLOSE1_HOME="$TMP_HOME/close1"
make_running_env "$CLOSE1_HOME"
printf '%s\n' '#!/usr/bin/env sh' 'exit 1' > "$CLOSE1_HOME/bin/pgrep"
chmod +x "$CLOSE1_HOME/bin/pgrep"
write_fake_pkill "$CLOSE1_HOME/bin"
CLOSE1_LOG="$CLOSE1_HOME/close.log"
CLOSE1_PKILL_BEFORE="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if ! PATH="$CLOSE1_HOME/bin:$PATH" bash "$CLOSE_SCRIPT" > "$CLOSE1_LOG" 2>&1 < /dev/null; then
    echo "close script: must exit 0 when nothing is running"
    cat "$CLOSE1_LOG"
    exit 1
fi
grep -Fq '无需操作' "$CLOSE1_LOG" || { echo "close script: expected a no-op message"; cat "$CLOSE1_LOG"; exit 1; }
CLOSE1_PKILL_AFTER="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if [ "$CLOSE1_PKILL_BEFORE" != "$CLOSE1_PKILL_AFTER" ]; then
    echo "close script: must not call pkill when nothing is running"
    exit 1
fi
echo "close script (nothing running): no-op"

# 4b. GUI 在跑：应当关掉它并报告成功
CLOSE2_HOME="$TMP_HOME/close2"
make_running_env "$CLOSE2_HOME"
CLOSE2_STATE="$CLOSE2_HOME/gui-running"
: > "$CLOSE2_STATE"
cat > "$CLOSE2_HOME/bin/pgrep" <<FAKE
#!/usr/bin/env sh
if [ -f "$CLOSE2_STATE" ]; then
    case "\$*" in
        *"-u "*) echo 4242; exit 0 ;;
    esac
fi
exit 1
FAKE
cat > "$CLOSE2_HOME/bin/pkill" <<FAKE
#!/usr/bin/env sh
printf "%s\n" "\$*" >> "\${FAKE_PKILL_LOG:-/dev/null}"
rm -f "$CLOSE2_STATE"
exit 0
FAKE
chmod +x "$CLOSE2_HOME/bin/pgrep" "$CLOSE2_HOME/bin/pkill"
CLOSE2_LOG="$CLOSE2_HOME/close.log"
CLOSE2_PKILL_BEFORE="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if ! PATH="$CLOSE2_HOME/bin:$PATH" bash "$CLOSE_SCRIPT" > "$CLOSE2_LOG" 2>&1 < /dev/null; then
    echo "close script: must exit 0 after stopping the GUI"
    cat "$CLOSE2_LOG"
    exit 1
fi
grep -Fq '都已关闭' "$CLOSE2_LOG" || { echo "close script: expected a success message"; cat "$CLOSE2_LOG"; exit 1; }
CLOSE2_PKILL_AFTER="$(wc -l < "$FAKE_PKILL_LOG" | tr -d ' ')"
if [ "$CLOSE2_PKILL_BEFORE" = "$CLOSE2_PKILL_AFTER" ]; then
    echo "close script: must call pkill to stop the running GUI"
    exit 1
fi
echo "close script (GUI running): stops it and reports success"

# 4c. 安装器清退失败时，提示必须指向这个文件
grep -Fq 'macOS关闭Clash.command' "$RUN3_LOG" || {
    echo "installer must point at the close script when it cannot stop the GUI"
    cat "$RUN3_LOG"
    exit 1
}
echo "installer points at the close script"

echo "Installer regression tests passed"
