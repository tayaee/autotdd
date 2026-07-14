#!/usr/bin/env bash
# minimaxcli — LLM wrapper that re-points the Claude CLI at the MiniMax
# coding-plan endpoint (CONTEXT.md "LLM 래퍼"). Named minimaxcli, not
# minimax, to avoid colliding with any real `minimax` CLI. Ported from the
# reference implementation at /rosenas/data/util/minimax3-claude.bat.
#
# Argument convention (shared with claudecli.sh): if $1 is an existing
# file, its content is piped to `claude ... -p` on stdin; otherwise every
# argument is passed straight through.
set -euo pipefail

if [ -z "${MINIMAX_API_KEY:-}" ]; then
    echo "[원인] MINIMAX_API_KEY 환경변수가 설정되지 않았습니다." >&2
    echo "[조치] MINIMAX_API_KEY를 설정한 뒤 다시 실행하세요 (예: export MINIMAX_API_KEY=...)." >&2
    exit 1
fi

MODEL=MiniMax-M3

export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
export ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY"
export API_TIMEOUT_MS=3000000
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"

# mitmproxy CA: never clobber a caller-provided NODE_EXTRA_CA_CERTS; only
# fill it in from the default mitmproxy cert location if unset.
if [ -z "${NODE_EXTRA_CA_CERTS:-}" ] && [ -f "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" ]; then
    export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
fi

# `claude` is resolved via PATH (never hardcoded), so tests can shadow it
# with a fake by prepending a directory to PATH.
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
    cat "$1" | claude --model="$MODEL" --dangerously-skip-permissions -p
else
    exec claude --model="$MODEL" --dangerously-skip-permissions "$@"
fi
