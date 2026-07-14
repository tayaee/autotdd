#!/usr/bin/env bash
# claudecli — LLM wrapper for the Claude Code coding plan (CONTEXT.md
# "LLM 래퍼"). Named claudecli, not claude, to avoid colliding with the
# real CLI it wraps. Ported from the reference implementation at
# /rosenas/data/util/sonnet.bat.
#
# Argument convention (shared with minimaxcli.sh): if $1 is an existing
# file, its content is piped to `claude ... -p` on stdin; otherwise every
# argument is passed straight through.
set -euo pipefail

MODEL=sonnet

# mitmproxy CA: never clobber a caller-provided NODE_EXTRA_CA_CERTS; only
# fill it in from the default mitmproxy cert location if unset.
if [ -z "${NODE_EXTRA_CA_CERTS:-}" ] && [ -f "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" ]; then
    export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
fi

# `claude` is resolved via PATH (never hardcoded), so tests can shadow it
# with a fake by prepending a directory to PATH.
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
    cat "$1" | claude --model "$MODEL" --effort medium --permission-mode=bypassPermissions -p
else
    exec claude --model "$MODEL" --effort medium --permission-mode=bypassPermissions "$@"
fi
