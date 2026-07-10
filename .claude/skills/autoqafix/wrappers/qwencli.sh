#!/usr/bin/env bash
# qwencli — pass-through LLM wrapper for the local `qwen` CLI (CONTEXT.md
# "LLM 래퍼"). Named qwencli, not qwen, to avoid self-invocation collision
# with the real CLI it wraps (`qwen.{bat,ps1,sh}` are forbidden names).
#
# Argument convention (shared with claudecli.sh/minimaxcli.sh/...): if $1
# is an existing file, its content is piped to `qwen -p` on stdin;
# otherwise every argument is passed straight through.
set -euo pipefail

CLI=qwen

if ! command -v "$CLI" > /dev/null 2>&1; then
    echo "[원인] $CLI CLI가 PATH에 없음" >&2
    echo "[조치] $CLI 설치 또는 PATH 추가" >&2
    exit 127
fi

if [ "$#" -ge 1 ] && [ -f "$1" ]; then
    cat "$1" | "$CLI" -p
else
    exec "$CLI" "$@"
fi
