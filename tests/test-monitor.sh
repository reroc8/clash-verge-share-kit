#!/usr/bin/env bash
# clash-monitor.sh 回归测试：stub 掉 curl 提供固定响应，不碰真实内核。
# 覆盖四个曾经的缺陷：
#   1. 大响应：整个 JSON 曾经作为命令行参数传给 python，连接数上千就 E2BIG
#   2. 负增量：连接累计值回退时不得写成负流量（此前会写 -0.07MB 这类行）
#   3. 共享状态：状态文件曾经固定写 /tmp，两个实例并发会互相覆盖
#   4. 时长语义：DURATION 曾经按「轮数」计（3 = 3 个 5 秒周期），必须是秒
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clash-monitor-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export FAKE_COUNTER="$WORK/counter"
export FAKE_A="$WORK/a.json"
export FAKE_B="$WORK/b.json"
export FAKE_C="$WORK/c.json"
export FAKE_REST=""
export FAKE_PROXIES="$WORK/proxies.json"
export FAKE_PROVIDERS="$WORK/providers.json"
printf '%s\n' '{"proxies":{"US-A":{"type":"Http"}}}' > "$FAKE_PROXIES"
printf '%s\n' '{"providers":{}}' > "$FAKE_PROVIDERS"
: > "$FAKE_COUNTER"

# A：大响应（> 1MB，超过 argv 长度上限），基线
# B：累计量回退（模拟连接关闭），用于验证负增量不落库
# C：A 的第一条连接多 5MB，用于验证正增量能正常落库
python3 - "$FAKE_A" "$FAKE_B" "$FAKE_C" <<'PY'
import json, sys

path_a, path_b, path_c = sys.argv[1:4]
MB = 1048576


def write(path, upload, download, bump_first=0):
    conns = []
    for i in range(1800):
        conns.append({
            "id": str(i),
            "chains": ["US-A", "AI"],
            "upload": upload + i,
            "download": download + i,
            "metadata": {
                "processPath": "/Applications/Alpha.app/Contents/MacOS/Alpha",
                "host": "h" * 600,
            },
        })
    conns[0]["upload"] += bump_first
    json.dump({"connections": conns}, open(path, "w"))


write(path_a, 3000000, 5000000)
write(path_b, 2000000, 4000000)
write(path_c, 3000000, 5000000, bump_first=5 * MB)
PY

if [ "$(wc -c < "$FAKE_A" | tr -d ' ')" -le 1048576 ]; then
    echo "monitor test: fixture A must exceed the 1MB argv limit"
    exit 1
fi

# stub curl：第一次返回 A（基线），之后返回 $FAKE_REST。
mkdir -p "$WORK/bin-curl" "$WORK/bin-fast"
cat > "$WORK/bin-curl/curl" <<'FAKE'
#!/usr/bin/env sh
case "$*" in
  *http://localhost/providers/proxies*) cat "$FAKE_PROVIDERS"; exit 0 ;;
  *http://localhost/proxies*) cat "$FAKE_PROXIES"; exit 0 ;;
esac
n=0
[ -f "$FAKE_COUNTER" ] && n=$(cat "$FAKE_COUNTER")
n=$((n + 1))
printf '%s\n' "$n" > "$FAKE_COUNTER"
if [ "$n" -le 1 ] || [ -z "$FAKE_REST" ]; then
  cat "$FAKE_A"
else
  cat "$FAKE_REST"
fi
FAKE
chmod +x "$WORK/bin-curl/curl"
cp "$WORK/bin-curl/curl" "$WORK/bin-fast/curl"
# bin-fast 里 sleep 是空操作：前两个场景只关心采样正确性，不需要真的等
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$WORK/bin-fast/sleep"
chmod +x "$WORK/bin-fast/sleep"

rounds_from() {
    local rounds
    rounds=$(grep -Eo '（[0-9]+ 轮）' "$1" 2>/dev/null | grep -Eo '[0-9]+' | head -1 || true)
    printf '%s\n' "${rounds:-0}"
}

# ── 场景 1：1.2MB 大响应可采样、正增量落库、状态目录是本次运行私有的 ──
mkdir -p "$WORK/tmp1"
if ! PATH="$WORK/bin-fast:$PATH" FAKE_REST="$FAKE_C" CLASH_SOCK="$WORK/fake.sock" \
    TMPDIR="$WORK/tmp1" bash "$ROOT_DIR/scripts/clash-monitor.sh" 2 "$WORK/run1.log" \
    > "$WORK/run1.out" 2>&1; then
    echo "monitor: large-response scenario failed"
    cat "$WORK/run1.out"
    exit 1
fi
if grep -q '采样失败' "$WORK/run1.out"; then
    echo "monitor: 1.2MB response must be sampled without Argument-list-too-long"
    cat "$WORK/run1.out"
    exit 1
fi
if [ "$(rounds_from "$WORK/run1.out")" -lt 2 ]; then
    echo "monitor: expected at least 2 rounds, got $(rounds_from "$WORK/run1.out")"
    cat "$WORK/run1.out"
    exit 1
fi
if grep -Eq '^[^,]+,[^,]+,(-[0-9]|-[0-9]+\.[0-9])' "$WORK/run1.log"; then
    echo "monitor: negative deltas must never be written to the CSV"
    cat "$WORK/run1.log"
    exit 1
fi
if ! grep -Fq ',Alpha,5.000000,0.000000,1800,proxy' "$WORK/run1.log"; then
    echo "monitor: expected the 5MB upload delta row"
    cat "$WORK/run1.log"
    exit 1
fi
if ls "$WORK/tmp1"/clash-monitor-* >/dev/null 2>&1; then
    echo "monitor: per-run state directory must be cleaned up on exit"
    ls -d "$WORK/tmp1"/clash-monitor-*
    exit 1
fi

# ── 场景 2：累计量回退（连接关闭）不得写成负增量 ──
mkdir -p "$WORK/tmp2"
: > "$FAKE_COUNTER"
if ! PATH="$WORK/bin-fast:$PATH" FAKE_REST="$FAKE_B" CLASH_SOCK="$WORK/fake.sock" \
    TMPDIR="$WORK/tmp2" bash "$ROOT_DIR/scripts/clash-monitor.sh" 2 "$WORK/run2.log" \
    > "$WORK/run2.out" 2>&1; then
    echo "monitor: counter-rollback scenario failed"
    cat "$WORK/run2.out"
    exit 1
fi
if grep -q '采样失败' "$WORK/run2.out"; then
    echo "monitor: counter-rollback scenario could not sample"
    cat "$WORK/run2.out"
    exit 1
fi
if [ "$(rounds_from "$WORK/run2.out")" -lt 2 ]; then
    echo "monitor: counter-rollback scenario needs at least 2 rounds, got $(rounds_from "$WORK/run2.out")"
    cat "$WORK/run2.out"
    exit 1
fi
if [ "$(wc -l < "$WORK/run2.log" | tr -d ' ')" -ne 1 ]; then
    echo "monitor: counter rollback must not produce any delta rows"
    cat "$WORK/run2.log"
    exit 1
fi

# ── 场景 3：DURATION 按秒计（旧实现 3 = 3 轮 × 5 秒 ≈ 15 秒） ──
mkdir -p "$WORK/tmp3"
: > "$FAKE_COUNTER"
RUN3_START=$(date +%s)
if ! PATH="$WORK/bin-curl:$PATH" FAKE_REST="$FAKE_C" CLASH_SOCK="$WORK/fake.sock" \
    TMPDIR="$WORK/tmp3" bash "$ROOT_DIR/scripts/clash-monitor.sh" 3 "$WORK/run3.log" \
    > "$WORK/run3.out" 2>&1; then
    echo "monitor: duration scenario failed"
    cat "$WORK/run3.out"
    exit 1
fi
RUN3_ELAPSED=$(( $(date +%s) - RUN3_START ))
if [ "$RUN3_ELAPSED" -gt 8 ]; then
    echo "monitor: DURATION must be seconds, but 3 took ${RUN3_ELAPSED}s"
    exit 1
fi
if [ "$RUN3_ELAPSED" -lt 2 ]; then
    echo "monitor: finished after ${RUN3_ELAPSED}s, expected roughly 3s"
    exit 1
fi

# ── 场景 4：旧连接关闭不能抵消同进程另一条连接的新增流量 ──
python3 - "$WORK/rollover-a.json" "$WORK/rollover-b.json" <<'PY'
import json, sys
MB = 1048576
def conn(ident, mb):
    return {"id": ident, "upload": mb * MB, "download": 0,
            "chains": ["US-A", "AI"], "metadata": {"process": "Alpha"}}
for path, rows in zip(sys.argv[1:], [[conn("closed", 100), conn("alive", 0)], [conn("alive", 20)]]):
    with open(path, "w") as handle:
        json.dump({"connections": rows}, handle)
PY
mkdir -p "$WORK/tmp4"
: > "$FAKE_COUNTER"
PATH="$WORK/bin-fast:$PATH" FAKE_A="$WORK/rollover-a.json" FAKE_REST="$WORK/rollover-b.json" \
    CLASH_SOCK="$WORK/fake.sock" TMPDIR="$WORK/tmp4" \
    bash "$ROOT_DIR/scripts/clash-monitor.sh" 2 "$WORK/run4.log" > "$WORK/run4.out" 2>&1
if ! grep -Fq ',Alpha,20.' "$WORK/run4.log"; then
    echo "monitor: closed 100MB connection must not cancel a surviving connection's 20MB increment"
    cat "$WORK/run4.log"
    exit 1
fi

# ── 场景 5：不能向旧版五列日志追加新版六列数据 ──
printf '%s\n' 'timestamp,process,upload_delta_mb,download_delta_mb,connections' > "$WORK/legacy.log"
cp "$WORK/legacy.log" "$WORK/legacy-before.log"
LEGACY_EXIT=0
PATH="$WORK/bin-fast:$PATH" CLASH_SOCK="$WORK/fake.sock" \
    bash "$ROOT_DIR/scripts/clash-monitor.sh" 1 "$WORK/legacy.log" > "$WORK/legacy.out" 2>&1 || LEGACY_EXIT=$?
if [ "$LEGACY_EXIT" -ne 2 ] || ! cmp -s "$WORK/legacy.log" "$WORK/legacy-before.log"; then
    echo "monitor: old-format log must be rejected without modification"
    exit 1
fi
grep -Fq '日志格式不同' "$WORK/legacy.out"

# 只拷贝 shell 启动器时要立即失败，不得循环重试并最终报成功。
cp "$ROOT_DIR/scripts/clash-monitor.sh" "$WORK/standalone.sh"
MISSING_EXIT=0
bash "$WORK/standalone.sh" 1 "$WORK/missing.log" > "$WORK/missing.out" 2>&1 || MISSING_EXIT=$?
if [ "$MISSING_EXIT" -ne 1 ] || [ -e "$WORK/missing.log" ]; then
    echo "monitor: missing accounting module must fail before sampling"
    exit 1
fi
grep -Fq '缺少同目录的 monitor-traffic.py' "$WORK/missing.out"

python3 -B "$ROOT_DIR/tests/test-monitor-traffic.py"
echo "Monitor script regression tests passed"
