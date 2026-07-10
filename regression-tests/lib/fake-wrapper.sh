#!/usr/bin/env bash
# Stand-in for LLM CLI wrappers (claudecli/minimaxcli/qwencli/...) used by
# regression tests so nothing spends real LLM credit. Behavior is selected
# via env FAKE_MODE (default: ok):
#   ok      - print FAKE_OUTPUT_FILE's contents if set+exists, else "pong"
#   fail    - print a message to stderr and exit 1
#   hang    - sleep 600s (simulates a stuck call)
#   archive - git mv env FAKE_TARGET into issues/archive/YYYY/MM/DD/ in the
#             cwd's git repo, commit, and push (mimics a successful autotdd
#             run archiving its issue)
#
# Every invocation's full argument list is appended as one line to
# env FAKE_LOG (if set), for call-verification in tests.
set -uo pipefail

if [ -n "${FAKE_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_LOG"
fi

mode="${FAKE_MODE:-ok}"

case "$mode" in
    ok)
        if [ -n "${FAKE_OUTPUT_FILE:-}" ] && [ -f "$FAKE_OUTPUT_FILE" ]; then
            cat "$FAKE_OUTPUT_FILE"
        else
            echo "pong"
        fi
        exit 0
        ;;
    fail)
        echo "fake-wrapper.sh: simulated failure (FAKE_MODE=fail)" >&2
        exit 1
        ;;
    hang)
        sleep 600
        exit 0
        ;;
    archive)
        if [ -z "${FAKE_TARGET:-}" ]; then
            echo "fake-wrapper.sh: FAKE_MODE=archive requires FAKE_TARGET" >&2
            exit 1
        fi
        if [ ! -f "$FAKE_TARGET" ]; then
            echo "fake-wrapper.sh: FAKE_TARGET '$FAKE_TARGET' not found" >&2
            exit 1
        fi
        dest_dir="issues/archive/$(date +%Y/%m/%d)"
        mkdir -p "$dest_dir"
        git mv "$FAKE_TARGET" "$dest_dir/" || exit 1
        git commit -q -m "archive: $(basename "$FAKE_TARGET")" || exit 1
        git push -q || exit 1
        exit 0
        ;;
    *)
        echo "fake-wrapper.sh: unknown FAKE_MODE '$mode'" >&2
        exit 1
        ;;
esac
