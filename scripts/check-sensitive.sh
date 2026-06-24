#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SENSITIVE_PATTERN='(^[[:space:]]*(proxies|proxy-providers):[[:space:]]*$|^[[:space:]-]*(server|password|uuid|cipher|alterId|client-fingerprint|private-key|servername|sni|skip-cert-verify):[[:space:]]*|https?://[^[:space:]"]*(token=|subscribe|subscription|api/v1/client/subscribe|api/v1/passport/auth/subscribe))'

if rg -n -i "$SENSITIVE_PATTERN" \
    "$ROOT_DIR/config" \
    "$ROOT_DIR/install" \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/README.md" \
    "$ROOT_DIR/SECURITY.md" \
    "$ROOT_DIR/docs" >/tmp/clash-verge-share-kit-sensitive.txt; then
    echo "敏感信息扫描失败，疑似包含订阅、节点或 token:"
    cat /tmp/clash-verge-share-kit-sensitive.txt
    exit 1
fi

echo "敏感信息扫描通过"
