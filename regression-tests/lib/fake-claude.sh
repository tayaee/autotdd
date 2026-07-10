#!/usr/bin/env bash
# Stand-in for the real `claude` CLI, used by regression tests so nothing
# spends real LLM credit. Logs every argument received to env FAKE_LOG (if
# set) as one line, captures stdin to env FAKE_STDIN_FILE (if set, for
# testing wrappers' file-argument piping), prints "pong", and exits 0.
set -uo pipefail

if [ -n "${FAKE_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_LOG"
fi

if [ -n "${FAKE_STDIN_FILE:-}" ]; then
    cat > "$FAKE_STDIN_FILE"
fi

echo "pong"
exit 0
