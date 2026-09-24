#!/usr/bin/env bash
# Clash Verge Rev share kit installer for macOS.
# Install Clash Verge Rev, import your own subscription, run it once, then quit it before running this script.
set -euo pipefail

CLASH_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
PACKAGE_VERSION="dev"
BACKUP_DIR=""
CREATED_FILES_LIST=""
INSTALL_STARTED=0
INSTALL_COMPLETED=0

for version_file in "$SCRIPT_DIR/VERSION.txt" "$SCRIPT_DIR/../VERSION.txt"; do
    if [ -f "$version_file" ]; then
        PACKAGE_VERSION="$(tr -d '\r\n' < "$version_file")"
        break
    fi
done

cleanup_old_backups() {
    installer_backups="$(
        while IFS= read -r backup_path; do
            if [ -f "$backup_path/.installer-backup" ]; then
                printf '%s\n' "$backup_path"
            fi
        done < <(find "$CLASH_DIR" -maxdepth 1 -type d -name 'backup_*' -print 2>/dev/null)
    )"
    old_backups="$(printf '%s\n' "$installer_backups" | sort -r | awk 'NF && NR > 5')"
    if [ -n "$old_backups" ]; then
        cleanup_count=0
        while IFS= read -r old_backup; do
            if rm -rf "$old_backup"; then
                cleanup_count=$((cleanup_count + 1))
            else
                echo "警告: 无法清理旧的自动备份: $old_backup"
            fi
        done <<< "$old_backups"
        if [ "$cleanup_count" -gt 0 ]; then
            echo ">>> 已清理安装器旧备份，仅保留最近 5 个自动备份目录；手工备份不会删除"
        fi
    fi
}

pause_before_close() {
    # 仅在 stdin 与 stdout 都是终端时才暂停。stdout 被重定向时（自动化脚本、
    # 回归测试、双击发版脚本）调用方看不到提示，read 会静默阻塞成假死。
    [ -t 0 ] && [ -t 1 ] || return 0
    echo ""
    read -r -p "按回车键关闭窗口..." _ || true
}

backup_existing_file() {
    src="$1"
    backup_name="$2"

    if [ -f "$src" ]; then
        backup_path="$BACKUP_DIR/$backup_name"
        if [ ! -f "$backup_path" ]; then
            mkdir -p "$(dirname "$backup_path")"
            cp "$src" "$backup_path"
        fi
    elif [ -n "${CREATED_FILES_LIST:-}" ]; then
        if ! grep -Fqx -- "$src" "$CREATED_FILES_LIST" 2>/dev/null; then
            printf '%s\n' "$src" >> "$CREATED_FILES_LIST"
        fi
    fi
}

restore_from_backup() {
    [ "$INSTALL_STARTED" = "1" ] || return 0
    [ "$INSTALL_COMPLETED" = "0" ] || return 0
    [ -n "${BACKUP_DIR:-}" ] || return 0
    [ -d "$BACKUP_DIR" ] || return 0

    echo ">>> 检测到安装未完成，正在尝试恢复安装前配置..."

    if [ -f "${CREATED_FILES_LIST:-}" ]; then
        while IFS= read -r created_file; do
            [ -n "$created_file" ] || continue
            if [ -f "$created_file" ]; then
                if rm -f "$created_file"; then
                    :
                else
                    echo "警告: 无法移除安装中新建的文件: $created_file"
                fi
            fi
        done < "$CREATED_FILES_LIST"
    fi

    restored_count=0
    for restore_scope in root profiles; do
        scope_dir="$BACKUP_DIR/$restore_scope"
        [ -d "$scope_dir" ] || continue
        while IFS= read -r backup_file; do
            [ -f "$backup_file" ] || continue
            relative_path="${backup_file#"$scope_dir/"}"
            if [ "$restore_scope" = "root" ]; then
                restore_path="$CLASH_DIR/$relative_path"
            else
                restore_path="$CLASH_DIR/profiles/$relative_path"
            fi
            mkdir -p "$(dirname "$restore_path")"
            if cp "$backup_file" "$restore_path"; then
                restored_count=$((restored_count + 1))
            else
                echo "警告: 恢复失败: $restore_path"
            fi
        done < <(find "$scope_dir" -type f -print)
    done

    echo ">>> 已尝试恢复 $restored_count 个备份文件"
}

on_exit() {
    code="$1"
    if [ "$code" -ne 0 ]; then
        echo ""
        restore_from_backup
        echo "安装未完成，请检查上面的错误信息。"
        pause_before_close
    fi
}

sync_profile_bound_files() {
    profiles_yaml="$CLASH_DIR/profiles.yaml"
    [ -f "$profiles_yaml" ] || return 0

    awk '
        NR == 1 { sub(/^\357\273\277/, "") }
        function clean_scalar(value) {
            sub(/^[[:space:]]*/, "", value)
            if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                value = substr(value, 2, length(value) - 2)
            } else {
                sub(/[[:space:]]+#.*$/, "", value)
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                    value = substr(value, 2, length(value) - 2)
                }
            }
            return value
        }
        function emit_item() {
            if (!in_item) {
                return
            }
            if (item_type == "merge" || item_type == "script") {
                if (file_name != "") {
                    print item_type "\t" file_name
                } else {
                    skipped_item = 1
                }
            }
        }
        function reset_item() {
            in_item = 0
            item_type = ""
            file_name = ""
        }
        /^-[[:space:]]*uid[[:space:]]*:/ {
            emit_item()
            reset_item()
            in_item = 1
            next
        }
        /^-[[:space:]]*/ {
            emit_item()
            reset_item()
            skipped_item = 1
            next
        }
        /^[[:space:]]+-[[:space:]]*(uid|type|file|\{)/ {
            emit_item()
            reset_item()
            skipped_item = 1
            next
        }
        in_item && /^  type[[:space:]]*:/ {
            type_value = $0
            sub(/^  type[[:space:]]*:[[:space:]]*/, "", type_value)
            type_value = clean_scalar(type_value)
            item_type = type_value
            next
        }
        in_item && /^  file[[:space:]]*:/ {
            file_value = $0
            sub(/^  file[[:space:]]*:[[:space:]]*/, "", file_value)
            file_name = clean_scalar(file_value)
            next
        }
        END {
            emit_item()
            if (skipped_item) {
                print "警告: profiles.yaml 含非标准条目，已跳过；仅支持 Clash Verge 生成的 - uid: 结构" > "/dev/stderr"
            }
        }
    ' "$profiles_yaml" | while IFS=$'\t' read -r item_type file_name; do
        case "$file_name" in
            ""|/*|*/*|*..*|*\\*)
                echo "警告: 跳过异常的订阅绑定文件名: $file_name"
                continue
                ;;
        esac
        backup_existing_file "$CLASH_DIR/profiles/$file_name" "profiles/$file_name"
        if [ "$item_type" = "merge" ]; then
            cp "$CONFIG_DIR/Merge.yaml" "$CLASH_DIR/profiles/$file_name"
        elif [ "$item_type" = "script" ]; then
            cp "$CONFIG_DIR/Script.js" "$CLASH_DIR/profiles/$file_name"
        fi
    done
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

# ── 运行中检测与清退 ──
# 三类进程，处理方式不同：
#   GUI    clash-verge（属主=当前用户）——退出时会回写 verge.yaml，安装前必须清退；
#          清退失败则中止安装。
#   内核   verge-mihomo / verge-mihomo-alpha / mihomo——只读配置，不会改写要安装的
#          文件；服务模式下由 root 启动，普通用户无权结束，故清退失败只警告不阻断。
#   服务   clash-verge-service（root，launchd RunAtLoad + KeepAlive 常驻）——退出 Clash
#          后它照样在跑，普通用户杀不掉，也不改写配置文件，因此不作为阻断条件。
# 注意：不能用宽松的 `pgrep -i "clash-verge"` 做整体判断——它会命中常驻的服务进程，
# 造成"已经退出 Clash 却仍被判定为在运行"（旧版就是这个行为）。GUI 判定必须带 -u。
CLASH_GUI_PATTERN="clash-verge"
CLASH_GUI_PATTERN_SPACED="clash verge"
CLASH_KERNEL_PATTERN="mihomo"

clash_gui_pids() {
    pgrep -u "$(id -u)" -i "$CLASH_GUI_PATTERN" 2>/dev/null
    pgrep -u "$(id -u)" -i "$CLASH_GUI_PATTERN_SPACED" 2>/dev/null
}

clash_kernel_pids() {
    pgrep -i "$CLASH_KERNEL_PATTERN" 2>/dev/null
}

terminate_clash_processes() {
    pkill -u "$(id -u)" -i "$CLASH_GUI_PATTERN" 2>/dev/null || true
    pkill -u "$(id -u)" -i "$CLASH_GUI_PATTERN_SPACED" 2>/dev/null || true
    pkill -i "$CLASH_KERNEL_PATTERN" 2>/dev/null || true
    sleep 1
    # 仍在的强杀
    if [ -n "$(clash_gui_pids)" ] || [ -n "$(clash_kernel_pids)" ]; then
        pkill -KILL -u "$(id -u)" -i "$CLASH_GUI_PATTERN" 2>/dev/null || true
        pkill -KILL -u "$(id -u)" -i "$CLASH_GUI_PATTERN_SPACED" 2>/dev/null || true
        pkill -KILL -i "$CLASH_KERNEL_PATTERN" 2>/dev/null || true
        sleep 1
    fi
}

if [ -n "$(clash_gui_pids)" ] || [ -n "$(clash_kernel_pids)" ]; then
    echo ">>> 检测到 Clash Verge Rev 或内核仍在运行，正在尝试清退..."
    terminate_clash_processes
fi

if [ -n "$(clash_gui_pids)" ]; then
    echo "错误: Clash Verge Rev 仍在运行，安装器无法自动清退"
    echo "请手动退出：点开 Clash Verge Rev 窗口，或用菜单栏图标里的「退出」"
    echo "（直接关窗口只是最小化到菜单栏，进程仍在运行）"
    exit 1
fi

if [ -n "$(clash_kernel_pids)" ]; then
    echo ">>> 提示: 内核仍在运行，且由管理员权限启动（服务模式），安装器无权结束它"
    echo ">>> 这不影响安装，但请安装完成后重新打开 Clash Verge Rev，让新配置生效"
    echo ">>> 若要立刻结束内核，可在 Clash Verge Rev 里关闭「服务模式」，或执行:"
    echo ">>>   sudo pkill -x verge-mihomo"
fi

echo ">>> 已确认 Clash Verge Rev 与内核均已退出"

mkdir -p "$CLASH_DIR/profiles"

BACKUP_DIR="$(mktemp -d "$CLASH_DIR/backup_${BACKUP_STAMP}_XXXXXX")"
# 安装器标记：只有带此标记的备份才会被自动清理，手工备份（含碰巧同名目录）不受影响
: > "$BACKUP_DIR/.installer-backup"
CREATED_FILES_LIST="$BACKUP_DIR/created-files.txt"
: > "$CREATED_FILES_LIST"

echo ">>> 安装前备份到: $BACKUP_DIR"

backup_existing_file "$CLASH_DIR/profiles/Merge.yaml" "profiles/Merge.yaml"
backup_existing_file "$CLASH_DIR/profiles/Script.js" "profiles/Script.js"
backup_existing_file "$CLASH_DIR/verge.yaml" "root/verge.yaml"
backup_existing_file "$CLASH_DIR/dns_config.yaml" "root/dns_config.yaml"

echo ">>> 正在安装..."
INSTALL_STARTED=1
sync_profile_bound_files
cp "$CONFIG_DIR/Merge.yaml"       "$CLASH_DIR/profiles/Merge.yaml"
cp "$CONFIG_DIR/Script.js"        "$CLASH_DIR/profiles/Script.js"
cp "$CONFIG_DIR/verge.yaml"       "$CLASH_DIR/verge.yaml"
cp "$CONFIG_DIR/dns_config.yaml"  "$CLASH_DIR/dns_config.yaml"
INSTALL_COMPLETED=1

cleanup_old_backups

echo ""
echo ">>> 安装完成。你的订阅和节点数据未被修改。"
echo ">>> 原文件已备份到: $BACKUP_DIR"
echo ">>> 如需还原: 完全退出 Clash Verge Rev 后，把备份目录里的文件复制回对应位置"
echo ">>>   backup/.../profiles/ -> $CLASH_DIR/profiles/"
echo ">>>   backup/.../root/ -> $CLASH_DIR/"
echo ">>> 配置文件已写入，并已同步已有订阅绑定的 merge/script 文件"
echo ">>> 重新打开 Clash Verge Rev 后即生效"
echo ">>> 安装后确认: 代理页能看到 Claude / AI / Google / YouTube / Telegram / Exchange / US / TW / SG / HK / JP / Proxies"
if [ -s "$CREATED_FILES_LIST" ]; then
    echo ">>> 提示: created-files.txt 里列出的文件在安装前不存在；精确还原时需要删除它们"
fi
echo ">>> 如果某类网站异常，先换对应策略组节点；如果规则集下载失败，请查看 Clash Verge Rev 日志"
echo ">>> 也可以按 README.txt 的“安装后 60 秒检查清单”逐项测试"
pause_before_close
