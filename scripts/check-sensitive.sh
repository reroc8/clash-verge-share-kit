#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/clash-verge-share-kit-sensitive.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

SENSITIVE_PATTERN='((^|[^[:alnum:]_-])["'"'"']?(server|password|uuid|cipher|alterId|client-fingerprint|private-key|servername|sni|skip-cert-verify|secret)["'"'"']?[[:space:]]*:|(^|[[:space:]{,])["'"'"']?(proxies|proxy-providers)["'"'"']?[[:space:]]*:[[:space:]]*([\[{]|$)|(ss|vmess|vless|trojan|hysteria2|tuic|wireguard)://[^[:space:]"'"'"'`、]+|https?://[^[:space:]"'"'"']*(token=|subscribe|subscription|api/v1/client/subscribe|api/v1/passport/auth/subscribe))'
if [ "$#" -gt 0 ]; then
    SCAN_TARGETS=("$@")
else
    SCAN_TARGETS=(
        "$ROOT_DIR/config"
        "$ROOT_DIR/install"
        "$ROOT_DIR/scripts"
        "$ROOT_DIR/tests"
        "$ROOT_DIR/README.md"
        "$ROOT_DIR/CHANGELOG.md"
        "$ROOT_DIR/SECURITY.md"
        "$ROOT_DIR/VERSION.txt"
        "$ROOT_DIR/docs"
    )
fi

if command -v rg >/dev/null 2>&1; then
    SCAN_TOOL="rg"
    SCAN_CMD=(rg -n -i "$SENSITIVE_PATTERN")
elif command -v grep >/dev/null 2>&1; then
    SCAN_TOOL="grep"
    SCAN_CMD=(grep -R -n -i -E "$SENSITIVE_PATTERN")
else
    echo "敏感信息扫描失败: 未找到 rg 或 grep"
    exit 1
fi

set +e
"${SCAN_CMD[@]}" "${SCAN_TARGETS[@]}" > "$TMP_FILE"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    # 豁免范围（均为合法测试/自指内容，凭据键与节点 URI 仍严格检查）：
    # 1) tests/ 目录测试夹具中的本地回环 server 地址（如 server: "127.0.0.1"）
    # 2) tests/ 目录测试夹具中的 proxies / proxy-providers 结构键行
    # 3) check-sensitive.sh 自身（模式定义中含键名与 URI 字面量）
    FILTERED="$(grep -v -i -E '/tests/[^:]+:[0-9]+:.*server:[[:space:]]*["'"'"']?(127\.0\.0\.1|localhost|::1)' "$TMP_FILE" \
        | grep -v -i -E '/tests/[^:]+:[0-9]+:.*["'"'"']?(proxies|proxy-providers)["'"'"']?[[:space:]]*:' \
        | grep -v -E '/check-sensitive\.sh:[0-9]+:' || true)"
    if [ -n "$FILTERED" ]; then
        echo "敏感信息扫描失败，疑似包含订阅、节点或 token:"
        printf '%s\n' "$FILTERED"
        exit 1
    fi
    echo "敏感信息扫描通过: 使用 $SCAN_TOOL（已豁免 tests/ 夹具与扫描器自指内容）"
    exit 0
fi

if [ "$STATUS" -ne 1 ]; then
    echo "敏感信息扫描失败: 扫描命令执行异常"
    exit "$STATUS"
fi

echo "敏感信息扫描通过: 使用 $SCAN_TOOL"
