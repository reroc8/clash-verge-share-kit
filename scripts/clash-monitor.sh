#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Clash Verge 连接监控：按进程聚合实时上传/下载流量
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
#   <脚本目录>/../monitor/clash-traffic.log   CSV: 时间,进程,上传增量MB,下载增量MB,连接数
#   终端实时打印每轮增量排行；每 30 秒打印一次本次会话累计 Top10
# ─────────────────────────────────────────────────────────────
set -euo pipefail

DURATION="${1:-0}"                      # 秒；0 = 无限
case "$DURATION" in
  *[!0-9]*)
    echo "用法: $0 [运行秒数] [日志文件]（运行秒数为 0 表示无限运行）" >&2
    exit 2
    ;;
esac
LOGDIR="$(cd "$(dirname "$0")/.." && pwd)/monitor"
LOGFILE="${2:-$LOGDIR/clash-traffic.log}"
mkdir -p "$LOGDIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 需要 python3 来聚合连接数据（macOS 自带；缺失可用 brew install python 安装）" >&2
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
STATE_FILE="$STATE_DIR/state.tsv"        # 上一轮每个进程的连接累计快照
TOTAL_FILE="$STATE_DIR/session.tsv"      # 本次会话累计增量
SNAP_FILE="$STATE_DIR/connections.json"  # 最近一次接口响应
ERR_FILE="$STATE_DIR/last-error.txt"
cleanup() { rm -rf "$STATE_DIR"; }
trap cleanup EXIT

fetch() { curl -s -f -m 5 --unix-socket "$SOCK" http://localhost/connections; }

SAMPLE_ERR=""

# 拉一轮连接快照：与上一轮比较后把增量行追加进 CSV，并在 stdout 打印本轮排行。
# 返回 1 表示本轮没采到（调用方会重试），原因写进 SAMPLE_ERR。
sample() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  # 响应先落盘再交给 python 读文件：整个 JSON 不能作为命令行参数传入——
  # 连接数上千时响应会超过系统 ARG_MAX（约 1MB），报 Argument list too long，
  # 而且 stderr 一丢，用户只会看到「内核未运行」这种误导性提示。
  if ! fetch > "$SNAP_FILE"; then
    SAMPLE_ERR="请求内核接口失败"
    return 1
  fi
  if ! python3 - "$SNAP_FILE" "$STATE_FILE" "$TOTAL_FILE" "$LOGFILE" "$ts" \
      > "$STATE_DIR/round.out" 2> "$ERR_FILE" <<'PYEOF'
import json, os, sys

snap_path, state_path, total_path, log_path, ts = sys.argv[1:6]
MB = 1048576.0

with open(snap_path, 'rb') as handle:
    data = json.load(handle)

agg = {}
for conn in data.get('connections') or []:
    meta = conn.get('metadata') or {}
    proc = (meta.get('processPath') or meta.get('process') or 'unknown').split('/')[-1]
    item = agg.setdefault(proc, [0, 0, 0])
    item[0] += conn.get('upload', 0) or 0
    item[1] += conn.get('download', 0) or 0
    item[2] += 1

first_sample = not os.path.exists(state_path)
before = {}
if not first_sample:
    with open(state_path) as handle:
        for line in handle:
            name, up, down, count = line.rstrip('\n').split('\t')
            before[name] = [int(up), int(down), int(count)]

with open(state_path, 'w') as handle:
    for name, (up, down, count) in agg.items():
        handle.write(f"{name}\t{up}\t{down}\t{count}\n")

if first_sample:
    top = sorted(agg.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))[:8]
    print(f"── {ts} 基线（连接累计总量） ──")
    for name, (up, down, count) in top:
        print(f"  {name:<28} ↑{up/MB:9.2f}MB ↓{down/MB:9.2f}MB  ({count}连接)")
    sys.exit(0)

session = {}
if os.path.exists(total_path):
    with open(total_path) as handle:
        for line in handle:
            name, up, down = line.rstrip('\n').split('\t')
            session[name] = [float(up), float(down)]

rows = []
with open(log_path, 'a') as log:
    for name, (up, down, count) in agg.items():
        if name not in before:
            # 本轮新出现的进程没有上一轮基线：它的连接累计总量不是这一轮的增量，
            # 跳过本轮，从下一轮开始按新基线计算。
            continue
        base_up, base_down, _ = before[name]
        # 连接关闭后内核的累计值会回退，这是计数重置而不是负流量：按 0 处理。
        delta_up = max(0, up - base_up) / MB
        delta_down = max(0, down - base_down) / MB
        if delta_up <= 0.001 and delta_down <= 0.001:
            continue
        log.write(f"{ts},{name},{delta_up:.3f},{delta_down:.3f},{count}\n")
        rows.append((name, delta_up, delta_down, count))
        acc = session.setdefault(name, [0.0, 0.0])
        acc[0] += delta_up
        acc[1] += delta_down

with open(total_path, 'w') as handle:
    for name, (up, down) in session.items():
        handle.write(f"{name}\t{up:.3f}\t{down:.3f}\n")

rows.sort(key=lambda row: -(row[1] + row[2]))
if rows:
    print(f"── {ts} ──")
    for name, up, down, count in rows[:8]:
        print(f"  {name:<28} ↑{up:+8.2f}MB ↓{down:+8.2f}MB  ({count}连接)")
PYEOF
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
  python3 - "$TOTAL_FILE" <<'PYEOF'
import sys
rows = []
try:
    with open(sys.argv[1]) as handle:
        for line in handle:
            name, up, down = line.rstrip('\n').split('\t')
            rows.append((name, float(up), float(down)))
except FileNotFoundError:
    sys.exit(0)
if not rows:
    sys.exit(0)
rows.sort(key=lambda row: -(row[1] + row[2]))
print("════ 本次会话累计 Top10（自启动起） ════")
for name, up, down in rows[:10]:
    print(f"  {name:<28} ↑{up:9.2f}MB ↓{down:9.2f}MB")
PYEOF
}

# CSV 表头只写一次（日志文件为空时）
if [ ! -s "$LOGFILE" ]; then
  echo "timestamp,process,upload_delta_mb,download_delta_mb,connections" > "$LOGFILE"
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
