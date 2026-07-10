#!/usr/bin/env bash
# Verifies issue-7 acceptance criteria: ping-<wrapper> diagnostic scripts
# for all 6 LLM wrappers.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
WRAPPERS="$REPO_ROOT/.claude/skills/autoqafix/wrappers"

FAIL=0
TMP_WORK="$(mktemp -d)"

cleanup() {
    [ -d "$TMP_WORK" ] && rm -rf "$TMP_WORK"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}

pass() {
    echo "PASS: $1"
}

WRAPPER_NAMES="claudecli minimaxcli qwencli codexcli antigravitycli deepseekcli"

# --- criterion: all 18 files exist; .sh 6 pass bash -n ---
for name in $WRAPPER_NAMES; do
    for ext in sh ps1 bat; do
        f="$WRAPPERS/ping-${name}.${ext}"
        if [ ! -f "$f" ]; then
            fail "missing $f"
        elif [ "$ext" = "sh" ]; then
            [ -x "$f" ] || fail "$f is not executable"
            bash -n "$f" || fail "$f has a bash syntax error"
        fi
    done
done

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing/invalid ping files"
    exit 1
fi

# --- criterion: PING_WRAPPER=fake-wrapper.sh (FAKE_MODE=ok) -> OK output, exit 0 ---
out="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=ok "$WRAPPERS/ping-claudecli.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK'; then
    pass "ping-claudecli.sh reports OK and exits 0 when the fake wrapper responds ok"
else
    fail "ping-claudecli.sh did not report OK/exit 0 for FAKE_MODE=ok (rc=$rc out='$out')"
fi

# --- criterion: FAKE_MODE=hang + PING_TIMEOUT=2 -> ~2s, exit 1 + timeout guidance ---
start_ts=$(date +%s)
out="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=hang PING_TIMEOUT=2 "$WRAPPERS/ping-claudecli.sh" 2>&1)"
rc=$?
end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
if [ "$rc" -ne 0 ] && [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 10 ] \
    && printf '%s' "$out" | grep -q '\[원인\]' && printf '%s' "$out" | grep -q '\[조치\]'; then
    pass "ping-claudecli.sh times out around 2s with [원인]/[조치] guidance (elapsed=${elapsed}s)"
else
    fail "ping-claudecli.sh timeout behavior wrong (rc=$rc elapsed=${elapsed}s out='$out')"
fi

# --- criterion: FAKE_MODE=fail -> exit 1 + [원인]/[조치] ---
out="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=fail "$WRAPPERS/ping-claudecli.sh" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '\[원인\]' && printf '%s' "$out" | grep -q '\[조치\]'; then
    pass "ping-claudecli.sh reports [원인]/[조치] and exits non-zero for FAKE_MODE=fail"
else
    fail "ping-claudecli.sh did not report [원인]/[조치] for FAKE_MODE=fail (rc=$rc out='$out')"
fi

# --- criterion (requirement 4, wrapper missing): non-existent PING_WRAPPER -> exit 1 + [원인]/[조치] ---
out="$(PING_WRAPPER="$TMP_WORK/does-not-exist.sh" "$WRAPPERS/ping-claudecli.sh" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '\[원인\]' && printf '%s' "$out" | grep -q '\[조치\]'; then
    pass "ping-claudecli.sh reports [원인]/[조치] when the wrapper file is missing"
else
    fail "ping-claudecli.sh did not report [원인]/[조치] for a missing wrapper (rc=$rc out='$out')"
fi

# --- sanity: every ping-<name>.sh honors PING_WRAPPER the same way ---
for name in $WRAPPER_NAMES; do
    out="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=ok "$WRAPPERS/ping-${name}.sh" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK'; then
        pass "ping-${name}.sh reports OK via PING_WRAPPER injection"
    else
        fail "ping-${name}.sh did not report OK via PING_WRAPPER injection (rc=$rc out='$out')"
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-7 acceptance checks passed."
    exit 0
else
    echo "One or more issue-7 acceptance checks failed."
    exit 1
fi
