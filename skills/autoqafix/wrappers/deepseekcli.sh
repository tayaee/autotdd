#!/usr/bin/env bash
# deepseekcli — pass-through LLM wrapper for the `deepseek` CLI
# (CONTEXT.md "LLM 래퍼"). Named deepseekcli, not deepseek, to avoid
# colliding with the real CLI it wraps. Split out of issue-4's
# claudecli/minimaxcli scope (issue-5) since `deepseek` may not be
# installed in every dev environment.
#
# FLAGS UNVERIFIED — 실 CLI 설치 환경에서 `deepseek --help`로 확인 후 조정할
# 것. This wrapper does no flag translation; it's a straight pass-through.
#
# Argument convention (shared with claudecli.sh/minimaxcli.sh/...): if $1
# is an existing file, its content is piped to `deepseek -p` on stdin;
# otherwise every argument is passed straight through.
set -euo pipefail

CLI=deepseek

if ! command -v "$CLI" > /dev/null 2>&1; then
    echo "[원인] $CLI가 PATH에 없음" >&2
    echo "[조치] $CLI 설치 또는 PATH 추가" >&2
    exit 127
fi

if [ "$#" -ge 1 ] && [ -f "$1" ]; then
    cat "$1" | "$CLI" -p
else
    exec "$CLI" "$@"
fi
