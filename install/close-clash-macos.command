#!/usr/bin/env bash
# 手动关闭 Clash Verge Rev 及其内核（Mihomo）。
#
# 用途：安装器提示「Clash Verge Rev 仍在运行」或「内核仍在运行」时，双击本文件。
# 说明：内核在服务模式下由管理员权限启动，普通权限结束不了，脚本会询问是否用管理员权限。
#       常驻助手 clash-verge-service 是系统服务，退出 Clash 后照常在跑，属正常，不影响安装。
set -euo pipefail

GUI_PATTERN="clash-verge"
GUI_PATTERN_SPACED="clash verge"
KERNEL_PATTERN="mihomo"
SERVICE_NAME="clash-verge-service"

gui_pids() {
    pgrep -u "$(id -u)" -i "$GUI_PATTERN" 2>/dev/null
    pgrep -u "$(id -u)" -i "$GUI_PATTERN_SPACED" 2>/dev/null
}

kernel_pids() {
    pgrep -i "$KERNEL_PATTERN" 2>/dev/null
}

service_pids() {
    pgrep -x "$SERVICE_NAME" 2>/dev/null
}

pause_before_close() {
    [ -t 0 ] && [ -t 1 ] || return 0
    echo ""
    read -r -p "按回车键关闭窗口..." _ || true
}

echo ">>> 关闭 Clash Verge Rev 及其内核"
echo ""

if [ -z "$(gui_pids)" ] && [ -z "$(kernel_pids)" ]; then
    echo ">>> 没有发现正在运行的 Clash Verge Rev 或内核，无需操作"
    if [ -n "$(service_pids)" ]; then
        echo ">>> 注: 常驻助手 $SERVICE_NAME 仍在运行，这是正常的，不影响安装"
    fi
    pause_before_close
    exit 0
fi

if [ -n "$(gui_pids)" ]; then
    echo ">>> 正在关闭 Clash Verge Rev（界面进程）..."
    pkill -u "$(id -u)" -i "$GUI_PATTERN" 2>/dev/null || true
    pkill -u "$(id -u)" -i "$GUI_PATTERN_SPACED" 2>/dev/null || true
fi

if [ -n "$(kernel_pids)" ]; then
    echo ">>> 正在关闭内核..."
    pkill -i "$KERNEL_PATTERN" 2>/dev/null || true
fi

sleep 1

if [ -n "$(gui_pids)" ] || [ -n "$(kernel_pids)" ]; then
    echo ">>> 有进程没响应，改用强制结束..."
    pkill -KILL -u "$(id -u)" -i "$GUI_PATTERN" 2>/dev/null || true
    pkill -KILL -u "$(id -u)" -i "$GUI_PATTERN_SPACED" 2>/dev/null || true
    pkill -KILL -i "$KERNEL_PATTERN" 2>/dev/null || true
    sleep 1
fi

if [ -n "$(gui_pids)" ]; then
    echo "错误: Clash Verge Rev 仍然没关掉"
    echo "请手动操作：点开 Clash Verge Rev 窗口，或用菜单栏图标里的「退出」"
    echo "（直接关窗口只是最小化到菜单栏，进程还在运行）"
    pause_before_close
    exit 1
fi

if [ -n "$(kernel_pids)" ]; then
    echo ">>> 内核仍在运行。它是服务模式下由管理员权限启动的，普通权限结束不了。"
    echo ">>> 它不会影响安装，可以不管；装完重新打开 Clash Verge Rev 即可。"
    if [ -t 0 ]; then
        echo ""
        read -r -p ">>> 现在用管理员权限结束内核？需要输入密码 [y/N] " kernel_answer || true
        case "${kernel_answer:-}" in
            [yY] | [yY][eE][sS])
                echo ">>> 请输入密码："
                sudo pkill -KILL -x verge-mihomo 2>/dev/null || true
                sudo pkill -KILL -x verge-mihomo-alpha 2>/dev/null || true
                sudo pkill -KILL -x mihomo 2>/dev/null || true
                sleep 1
                ;;
            *)
                echo ">>> 已跳过"
                ;;
        esac
    fi
fi

if [ -n "$(kernel_pids)" ]; then
    echo ""
    echo ">>> 结果: 内核仍在运行。安装不受影响；也可以在 Clash Verge Rev 里关闭「服务模式」后重试"
else
    echo ""
    echo ">>> 结果: Clash Verge Rev 及其内核都已关闭，现在可以运行安装器了"
fi

pause_before_close
