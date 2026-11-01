#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Clash Verge 连接监控：按连接 ID 计量，再按进程与代理/直连/未知聚合
# 通过内核 Unix socket 抓取，无需开启外部控制器 TCP 端口
#
# 用法:
#   ./clash-monitor.sh                 # 前台运行，Ctrl+C 停止
#   ./clash-monitor.sh 60              # 运行 60 秒后退出（单位：秒）
#   ./clash-monitor.sh 0 /tmp/out.log  # 无限运行，日志写 /tmp/out.log
#
# 接口地址：自动探测，也可用环境变量覆盖
#   CLASH_SOCK=/path/to.sock ./clash-monitor.sh
#
# 输出:
#   <脚本目录>/../monitor/clash-traffic-v2.log   CSV: 时间,进程,上传增量MB,下载增量MB,连接数,路径类型
#   终端实时打印每轮增量排行；每 30 秒打印一次本次会话累计 Top10
#   只计采样观察到的字节；采样间关闭的连接可能漏计，不等于机场账单。
#   需与同目录 monitor-traffic.py 一起使用。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

DURATION="${1:-0}"                      # 秒；0 = 无限
case "$DURATION" in
  *[!0-9]*)
    echo "用法: $0 [运行秒数] [日志文件]（运行秒数为 0 表示无限运行）" >&2
    exit 2
    ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$(cd "$SCRIPT_DIR/.." && pwd)/monitor"
LOGFILE="${2:-$LOGDIR/clash-traffic-v2.log}"
mkdir -p "$(dirname "$LOGFILE")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 需要 python3 来聚合连接数据（缺失可用 brew install python 安装）" >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/monitor-traffic.py" ]; then
  echo "错误: 缺少同目录的 monitor-traffic.py，请保留完整 scripts 目录" >&2
  exit 1
fi

# ── 内核接口地址 ──────────────────────────────────────────────
# Clash Verge Rev 2.5.4 起 macOS 上不再是固定的 /tmp/verge/verge-mihomo.sock：
#   · 服务模式（装了「服务」，内核由系统服务启动）→ /var/run/clash-verge-service/users/<uid>/verge-mihomo.sock
#   · 用户模式（Sidecar，没装服务）              → $TMPDIR/verge-mihomo.sock
# 注意：clash-verge.yaml 里的 external-controller-unix 在服务模式下写的仍是用户模式地址，
# 不代表当前真正在用的那个，所以这里一律自己探测，不读配置文件。
SOCK_OVERRIDE="${CLASH_SOCK:-}"
SOCK=""

sock_candidates() {
  # 服务模式：路径里带当前用户 ID
  printf '%s\n' "/var/run/clash-verge-service/users/$(id -u)/verge-mihomo.sock"
  # 用户模式：macOS 的每用户临时目录（TMPDIR 末尾自带斜杠，去掉再拼）
  local tmp="${TMPDIR:-/tmp}"
  printf '%s\n' "${tmp%/}/verge-mihomo.sock"
  # 2.5.4 之前的旧位置，保留用于兼容旧版内核
  printf '%s\n' "/tmp/verge/verge-mihomo.sock"
}

# 只判断文件存在不够：换过运行模式后，上一个模式留下的 socket 文件可能还在，
# 选中它就会一直采样失败。所以再确认一下它真的能应答。
# （上游服务同样是按「能不能连上」而不是「文件在不在」来判断的。）
sock_alive() {
  curl -s -m 2 -o /dev/null --unix-socket "$1" http://localhost/version
}

detect_sock() {
  if [ -n "$SOCK_OVERRIDE" ]; then
    SOCK="$SOCK_OVERRIDE"
    return 0
  fi
  local cand
  while IFS= read -r cand; do
    if [ -S "$cand" ] && sock_alive "$cand"; then
      SOCK="$cand"
      return 0
    fi
  done < <(sock_candidates)
  SOCK=""
  return 1
}

# 采样状态放本次运行的私有目录：两个实例同时跑不会互相覆盖。
# （此前状态文件固定写在 /tmp，两个实例会互相删状态、串数据。）
TMPROOT="${TMPDIR:-/tmp}"
STATE_DIR="${TMPROOT%/}/clash-monitor-$(id -u)-$$"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/state.json"       # 上一轮每个连接 ID 的字节计数
TOTAL_FILE="$STATE_DIR/session.json"     # 本次观测累计字节数，按进程和路径分类
SNAP_FILE="$STATE_DIR/connections.json"  # 最近一次接口响应
PROXIES_FILE="$STATE_DIR/proxies.json"
PROVIDERS_FILE="$STATE_DIR/providers.json"
ERR_FILE="$STATE_DIR/last-error.txt"
cleanup() { rm -rf "$STATE_DIR"; }
trap cleanup EXIT

fetch() { curl -s -f -m 5 --unix-socket "$SOCK" "http://localhost/$1"; }

SAMPLE_ERR=""

# 拉一轮连接快照：与上一轮比较后把增量行追加进 CSV，并在 stdout 打印本轮排行。
# 返回 1 表示本轮没采到（调用方会重试），原因写进 SAMPLE_ERR。
sample() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  # 响应先落盘再交给 python 读文件：整个 JSON 不能作为命令行参数传入——
  # 连接数上千时响应会超过系统 ARG_MAX（约 1MB），报 Argument list too long，
  # 而且 stderr 一丢，用户只会看到「内核未运行」这种误导性提示。
  if ! fetch connections > "$SNAP_FILE"; then
    SAMPLE_ERR="请求内核接口失败"
    return 1
  fi
  # 名称不是类型：自定义直连节点和 provider 节点都需要从 API 查实际类型。
  # 元数据缺失时继续采样，但归入 unknown，不能猜成代理流量。
  if ! fetch proxies > "$PROXIES_FILE"; then
    printf '{}\n' > "$PROXIES_FILE"
    echo "[$(date '+%H:%M:%S')] 无法读取节点类型，部分连接将标为未知" >&2
  fi
  if ! fetch providers/proxies > "$PROVIDERS_FILE"; then
    printf '{}\n' > "$PROVIDERS_FILE"
    echo "[$(date '+%H:%M:%S')] 无法读取 provider 节点类型，部分连接将标为未知" >&2
  fi
  if ! python3 "$SCRIPT_DIR/monitor-traffic.py" sample \
      "$SNAP_FILE" "$STATE_FILE" "$TOTAL_FILE" "$LOGFILE" "$ts" "$PROXIES_FILE" "$PROVIDERS_FILE" \
      > "$STATE_DIR/round.out" 2> "$ERR_FILE"
  then
    SAMPLE_ERR="解析内核响应失败（$(tail -n 1 "$ERR_FILE" 2>/dev/null | cut -c1-160)）"
    return 1
  fi
  if [ -s "$STATE_DIR/round.out" ]; then
    cat "$STATE_DIR/round.out"
  fi
  return 0
}

report_session() {
  python3 "$SCRIPT_DIR/monitor-traffic.py" report "$TOTAL_FILE"
}

# 不能把六列的新数据接在五列旧日志后面；旧文件保留不动。
LOG_HEADER="timestamp,process,upload_delta_mb,download_delta_mb,connections,route"
if [ -s "$LOGFILE" ]; then
  IFS= read -r EXISTING_HEADER < "$LOGFILE" || true
  if [ "${EXISTING_HEADER%$'\r'}" != "$LOG_HEADER" ]; then
    echo "错误: 日志格式不同，请指定新的日志文件；原日志未修改: $LOGFILE" >&2
    exit 2
  fi
else
  printf '%s\n' "$LOG_HEADER" > "$LOGFILE"
fi
if detect_sock; then
  echo "[监控启动] socket=$SOCK  日志=$LOGFILE  (Ctrl+C 停止)"
else
  echo "[监控启动] 暂未找到内核接口，日志=$LOGFILE  (Ctrl+C 停止)"
  echo "           已检查以下位置，内核起来后会自动重试：" >&2
  sock_candidates | sed 's/^/             /' >&2
  echo "           要手动指定：CLASH_SOCK=/路径 $0" >&2
fi

ITER=0
START=$(date +%s)
LAST_REPORT=$START
while true; do
  if [ -z "$SOCK" ]; then
    if detect_sock; then
      echo "[$(date '+%H:%M:%S')] 已连接到内核接口: $SOCK"
    fi
  fi
  SAMPLE_ERR=""
  if [ -n "$SOCK" ] && sample; then
    :
  else
    # 内核可能还没起来，或者换了运行模式（服务 ↔ 用户），下一轮重新探测
    [ -n "$SOCK_OVERRIDE" ] || SOCK=""
    if [ -n "$SAMPLE_ERR" ]; then
      echo "[$(date '+%H:%M:%S')] 采样失败（$SAMPLE_ERR），稍后重试" >&2
    else
      echo "[$(date '+%H:%M:%S')] 未找到内核接口，稍后重试" >&2
    fi
  fi

  ITER=$((ITER + 1))
  NOW=$(date +%s)
  # 每 30 秒打印一次本次会话累计排行
  if [ $((NOW - LAST_REPORT)) -ge 30 ]; then
    LAST_REPORT=$NOW
    report_session || true
  fi

  ELAPSED=$((NOW - START))
  if [ "$DURATION" != "0" ] && [ "$ELAPSED" -ge "$DURATION" ]; then
    report_session || true
    echo "[监控结束] 已运行 ${ELAPSED} 秒（${ITER} 轮），日志: $LOGFILE"
    exit 0
  fi
  if [ "$DURATION" != "0" ]; then
    REMAINING=$((DURATION - ELAPSED))
    if [ "$REMAINING" -lt 5 ]; then
      sleep "$REMAINING"
    else
      sleep 5
    fi
  else
    sleep 5
  fi
done
