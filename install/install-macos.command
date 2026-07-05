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

backup_existing_file() {
    src="$1"
    backup_name="$2"

    if [ -f "$src" ]; then
        if [ ! -f "$BACKUP_DIR/$backup_name" ]; then
            cp "$src" "$BACKUP_DIR/$backup_name"
        fi
    elif [ -n "${CREATED_FILES_LIST:-}" ]; then
        printf '%s\n' "$src" >> "$CREATED_FILES_LIST"
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
    for backup_file in "$BACKUP_DIR"/*; do
        [ -f "$backup_file" ] || continue
        file_name="$(basename "$backup_file")"
        case "$file_name" in
            verge.yaml|dns_config.yaml)
                restore_path="$CLASH_DIR/$file_name"
                ;;
            *)
                restore_path="$CLASH_DIR/profiles/$file_name"
                ;;
        esac

        if cp "$backup_file" "$restore_path"; then
            restored_count=$((restored_count + 1))
        else
            echo "警告: 恢复失败: $restore_path"
        fi
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
        /^- uid:/ { item_type = "" }
        /^[[:space:]]*type:[[:space:]]*(merge|script)[[:space:]]*$/ { item_type = $2 }
        /^[[:space:]]*file:[[:space:]]*/ {
            file = $2
            gsub(/"/, "", file)
            gsub(/'"'"'/, "", file)
            if (item_type == "merge" || item_type == "script") {
                print item_type " " file
            }
        }
    ' "$profiles_yaml" | while IFS=' ' read -r item_type file_name; do
        case "$file_name" in
            ""|/*|*..*|*\\*) continue ;;
        esac
        backup_existing_file "$CLASH_DIR/profiles/$file_name" "$file_name"
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

BACKUP_DIR="$(mktemp -d "$CLASH_DIR/backup_${BACKUP_STAMP}_XXXXXX")"
CREATED_FILES_LIST="$BACKUP_DIR/.created-files"
: > "$CREATED_FILES_LIST"

echo ">>> 安装前备份到: $BACKUP_DIR"

for file in "Merge.yaml" "Script.js" "verge.yaml" "dns_config.yaml"; do
    if [ "$file" = "Merge.yaml" ] || [ "$file" = "Script.js" ]; then
        backup_existing_file "$CLASH_DIR/profiles/$file" "$file"
    else
        backup_existing_file "$CLASH_DIR/$file" "$file"
    fi
done

echo ">>> 正在安装..."
INSTALL_STARTED=1
cp "$CONFIG_DIR/Merge.yaml"       "$CLASH_DIR/profiles/Merge.yaml"
cp "$CONFIG_DIR/Script.js"        "$CLASH_DIR/profiles/Script.js"
sync_profile_bound_files
cp "$CONFIG_DIR/verge.yaml"       "$CLASH_DIR/verge.yaml"
cp "$CONFIG_DIR/dns_config.yaml"  "$CLASH_DIR/dns_config.yaml"
INSTALL_COMPLETED=1

cleanup_old_backups

echo ""
echo ">>> 安装完成。你的订阅和节点数据未被修改。"
echo ">>> 原文件已备份到: $BACKUP_DIR"
echo ">>> 如需还原: 完全退出 Clash Verge Rev 后，把备份目录里的文件复制回对应位置"
echo ">>>   Merge.yaml / Script.js / 其它随机 .yaml .js -> $CLASH_DIR/profiles/"
echo ">>>   verge.yaml / dns_config.yaml -> $CLASH_DIR/"
echo ">>> 配置文件已写入，并已同步已有订阅绑定的 merge/script 文件"
echo ">>> 重新打开 Clash Verge Rev 后即生效"
echo ">>> 安装后确认: 代理页能看到 Claude / AI / US / Google / YouTube / Exchange"
echo ">>> 如果某类网站异常，先换对应策略组节点；如果规则集下载失败，请查看 Clash Verge Rev 日志"
echo ">>> 也可以按 README.txt 的“安装后 60 秒检查清单”逐项测试"
pause_before_close
