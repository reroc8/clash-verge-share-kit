#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Clash Verge 连接监控：按进程聚合实时上传/下载流量
# 通过内核 Unix socket 抓取，无需开启外部控制器 TCP 端口
#
# 用法:
#   ./clash-monitor.sh                 # 前台运行，Ctrl+C 停止
#   ./clash-monitor.sh 60              # 运行 60 秒后退出
#   ./clash-monitor.sh 0 /tmp/out.log  # 无限运行，日志写 /tmp/out.log
#
# 输出:
#   <脚本目录>/../monitor/clash-traffic.log   CSV: 时间,进程,上传增量MB,下载增量MB,连接数
#   终端实时打印 Top 进程排行（每 30 秒刷新一次）
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SOCK="${CLASH_SOCK:-/tmp/verge/verge-mihomo.sock}"
DURATION="${1:-0}"                      # 0 = 无限
LOGDIR="$(cd "$(dirname "$0")/.." && pwd)/monitor"
LOGFILE="${2:-$LOGDIR/clash-traffic.log}"
mkdir -p "$LOGDIR"

# 进程级累计状态持久化在 /tmp/clash-mon-state.txt（由 Python 维护）
# 每次启动重置状态：首轮只记基线不记增量，避免把连接累计总量当成增量
rm -f /tmp/clash-mon-state.txt /tmp/clash-mon-delta.txt

fetch() { curl -s -m 5 --unix-socket "$SOCK" http://localhost/connections; }

sample() {
  local json
  json=$(fetch) || return 1
  python3 - "$json" <<'PYEOF' > /tmp/clash-mon-delta.txt 2>/dev/null || return 1
import json, sys
d = json.loads(sys.argv[1])
agg = {}
for c in d.get('connections') or []:
    m = c['metadata']
    proc = (m.get('processPath') or m.get('process') or 'unknown').split('/')[-1]
    a = agg.setdefault(proc, [0, 0, 0])
    a[0] += c.get('upload', 0)
    a[1] += c.get('download', 0)
    a[2] += 1
for k, (u, dn, n) in agg.items():
    print(f"{k}\t{u}\t{dn}\t{n}")
PYEOF
}

# CSV 表头只写一次（日志文件为空时）
if [ ! -s "$LOGFILE" ]; then
  echo "timestamp,process,upload_delta_mb,download_delta_mb,connections" > "$LOGFILE"
fi
echo "[监控启动] socket=$SOCK  日志=$LOGFILE  (Ctrl+C 停止)"

ITER=0
LAST_REPORT=$(date +%s)
while true; do
  if sample; then
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    # 计算每个进程相对上一轮的增量并累计
    python3 - "$TS" "$LOGFILE" <<'PYEOF'
import sys, os, collections
ts, logfile = sys.argv[1], sys.argv[2]
first_sample = not os.path.exists('/tmp/clash-mon-state.txt')
before = collections.defaultdict(lambda: [0, 0, 0])
try:
    with open('/tmp/clash-mon-state.txt') as f:
        for line in f:
            k, u, dn, n = line.rstrip('\n').split('\t')
            before[k] = [int(u), int(dn), int(n)]
except FileNotFoundError:
    pass
now = {}
with open('/tmp/clash-mon-delta.txt') as f:
    for line in f:
        k, u, dn, n = line.rstrip('\n').split('\t')
        now[k] = [int(u), int(dn), int(n)]
if first_sample:
    # 基线轮：写入状态但不记增量（连接累计总量不是本轮产生）
    with open('/tmp/clash-mon-state.txt', 'w') as f:
        for k, (u, dn, n) in now.items():
            f.write(f"{k}\t{u}\t{dn}\t{n}\n")
    top = sorted(now.items(), key=lambda x: -(x[1][0] + x[1][1]))[:8]
    print(f"── {ts} 基线（连接累计总量） ──")
    for k, (u, dn, n) in top:
        print(f"  {k:<28} ↑{u/1048576:9.2f}MB ↓{dn/1048576:9.2f}MB  ({n}连接)")
    sys.exit(0)
with open('/tmp/clash-mon-state.txt', 'w') as f:
    for k, (u, dn, n) in now.items():
        f.write(f"{k}\t{u}\t{dn}\t{n}\n")
rows = []
for k, (u, dn, n) in now.items():
    bu, bd, _ = before.get(k, [0, 0, 0])
    du, dd = (u - bu) / 1048576, (dn - bd) / 1048576
    if abs(du) > 0.001 or abs(dd) > 0.001:
        rows.append((k, du, dd, n))
        with open(logfile, 'a') as lf:
            lf.write(f"{ts},{k},{du:.3f},{dd:.3f},{n}\n")
rows.sort(key=lambda r: -(r[1] + r[2]))
if rows:
    print(f"── {ts} ──")
    for k, du, dd, n in rows[:8]:
        print(f"  {k:<28} ↑{du:+8.2f}MB ↓{dd:+8.2f}MB  ({n}连接)")
PYEOF
  else
    echo "[$(date '+%H:%M:%S')] 采样失败（内核未运行或 socket 不可用）" >&2
  fi

  ITER=$((ITER + 1))
  # 每 30 秒打印一次跨周期累计排行
  NOW=$(date +%s)
  if [ $((NOW - LAST_REPORT)) -ge 30 ]; then
    LAST_REPORT=$NOW
    echo "════ 跨周期累计 Top10 ════"
    python3 - <<'PYEOF'
try:
    state = {}
    with open('/tmp/clash-mon-state.txt') as f:
        for line in f:
            k, u, dn, n = line.rstrip('\n').split('\t')
            state[k] = (int(u), int(dn), int(n))
    for k, (u, dn, n) in sorted(state.items(), key=lambda x: -(x[1][0] + x[1][1]))[:10]:
        print(f"  {k:<28} ↑{u/1048576:9.2f}MB ↓{dn/1048576:9.2f}MB  ({n}连接)")
except FileNotFoundError:
    pass
PYEOF
  fi

  if [ "$DURATION" != "0" ] && [ "$ITER" -ge "$DURATION" ]; then
    echo "[监控结束] 共 $ITER 轮，日志: $LOGFILE"
    exit 0
  fi
  sleep 5
done
