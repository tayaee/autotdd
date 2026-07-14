#!/usr/bin/env bash
# ping-deepseekcli — diagnostic: confirms deepseekcli actually responds. Manual /
# post-install / incident-time use only — never part of the automated
# preflight loop (that would burn LLM credit every cycle). See
# CONTEXT.md "LLM 래퍼".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_NAME=deepseekcli
WRAPPER="${PING_WRAPPER:-$SCRIPT_DIR/${WRAPPER_NAME}.sh}"
TIMEOUT="${PING_TIMEOUT:-120}"

if [ ! -f "$WRAPPER" ]; then
    echo "[원인] $WRAPPER_NAME 없음" >&2
    echo "[조치] autotdd 설치 확인" >&2
    exit 1
fi

start_ts=$(date +%s)
output="$(timeout "$TIMEOUT" "$WRAPPER" -p "respond with exactly: pong" 2>&1)"
rc=$?
elapsed=$(( $(date +%s) - start_ts ))

if [ "$rc" -eq 124 ]; then
    echo "[원인] ${TIMEOUT}초 내 무응답" >&2
    echo "[조치] 네트워크/서비스 상태, 쿼터 확인 (claude: claude.ai, qwen: 로컬 서비스 기동 여부)" >&2
    exit 1
fi

if [ "$rc" -eq 0 ] && printf '%s' "$output" | grep -q 'pong'; then
    echo "OK $WRAPPER_NAME (${elapsed}s)"
    exit 0
fi

echo "[원인] 응답 이상 (exit=$rc)" >&2
echo "[조치] $WRAPPER_NAME 단독 실행으로 에러 메시지 확인" >&2
exit 1
