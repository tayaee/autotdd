#!/usr/bin/env bash
# Stand-in for the real `claude` CLI, used by regression tests so nothing
# spends real LLM credit. Logs every argument received to env FAKE_LOG (if
# set) as one line, prints "pong", and exits 0.
set -uo pipefail

if [ -n "${FAKE_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_LOG"
fi

echo "pong"
exit 0
