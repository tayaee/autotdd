#!/usr/bin/env bash
# Stand-in for LLM CLI wrappers (claudecli/minimaxcli/qwencli/...) used by
# regression tests so nothing spends real LLM credit. Behavior is selected
# via env FAKE_MODE (default: ok):
#   ok           - print FAKE_OUTPUT_FILE's contents if set+exists, else "pong"
#   fail         - print a message to stderr and exit 1
#   hang         - sleep FAKE_HANG_SLEEP (default 600) seconds (stuck call)
#   archive      - git mv the target item into issues/archive/YYYY/MM/DD/ in
#                  the cwd's git repo, commit, and push (mimics a successful
#                  autotdd run archiving its issue)
#   archive_fail - archive (as above, push included) but then exit 1
#                  (wrapper does the work and dies abnormally)
#   dirty_fail   - commit an unpushed junk file in the cwd repo and exit 1
#                  (wrapper leaves partial work behind)
#
# The archive-family target is env FAKE_TARGET when set; otherwise it is
# derived from the dispatch prompt (`-p "/autotdd <stem> worktree"`): the
# second token's <stem> becomes issues/<stem>.md relative to the cwd.
#
# FAKE_MODE_MAP overrides FAKE_MODE per item: comma-separated
# `<stem>=<mode>` pairs (e.g. "autofix-1=fail,autofix-2=archive"), matched
# against the <stem> parsed from the prompt.
#
# Every invocation's full argument list is appended as one line to
# env FAKE_LOG (if set), for call-verification in tests.
set -uo pipefail

if [ -n "${FAKE_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_LOG"
fi

# Parse "<stem>" out of a dispatch prompt like "/autotdd autofix-1 worktree".
prompt=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-p" ]; then
        prompt="$arg"
        break
    fi
    prev="$arg"
done
stem=""
case "$prompt" in
    /autotdd\ *)
        stem="$(printf '%s' "$prompt" | awk '{print $2}')"
        ;;
esac

mode="${FAKE_MODE:-ok}"
if [ -n "${FAKE_MODE_MAP:-}" ] && [ -n "$stem" ]; then
    IFS=',' read -ra _pairs <<< "$FAKE_MODE_MAP"
    for _pair in "${_pairs[@]}"; do
        if [ "${_pair%%=*}" = "$stem" ]; then
            mode="${_pair#*=}"
        fi
    done
fi

resolve_target() {
    if [ -n "${FAKE_TARGET:-}" ]; then
        printf '%s' "$FAKE_TARGET"
    elif [ -n "$stem" ]; then
        printf 'issues/%s.md' "$stem"
    fi
}

do_archive() {
    local target
    target="$(resolve_target)"
    if [ -z "$target" ]; then
        echo "fake-wrapper.sh: archive needs FAKE_TARGET or a '/autotdd <stem>' prompt" >&2
        return 1
    fi
    if [ ! -f "$target" ]; then
        echo "fake-wrapper.sh: target '$target' not found" >&2
        return 1
    fi
    local dest_dir
    dest_dir="issues/archive/$(date +%Y/%m/%d)"
    mkdir -p "$dest_dir"
    git mv "$target" "$dest_dir/" || return 1
    git commit -q -m "archive: $(basename "$target")" || return 1
    # Detached-HEAD worktrees need the explicit refspec; plain clones
    # (verify-issue-3's fixture) work with it too.
    git push -q origin HEAD:main 2>/dev/null || git push -q || return 1
    return 0
}

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
        sleep "${FAKE_HANG_SLEEP:-600}"
        exit 0
        ;;
    archive)
        do_archive || exit 1
        exit 0
        ;;
    archive_fail)
        do_archive || exit 1
        echo "fake-wrapper.sh: died after archiving (FAKE_MODE=archive_fail)" >&2
        exit 1
        ;;
    dirty_fail)
        echo "junk" > junk.txt
        git add junk.txt
        git commit -q -m "wip: partial work"
        echo "fake-wrapper.sh: left a partial commit behind (FAKE_MODE=dirty_fail)" >&2
        exit 1
        ;;
    *)
        echo "fake-wrapper.sh: unknown FAKE_MODE '$mode'" >&2
        exit 1
        ;;
esac
