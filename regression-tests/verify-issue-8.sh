#!/usr/bin/env bash
# Verifies issue-8 acceptance criteria: usage-claudecli.py / usage-minimaxcli.py
# / usage-qwencli.py.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"

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

command -v uv > /dev/null 2>&1 || { echo "FAIL: uv not found on PATH, cannot verify PEP-723 scripts" >&2; exit 1; }

# --- criterion: all three files exist ---
for name in usage-claudecli usage-minimaxcli usage-qwencli; do
    [ -f "$SKILL_DIR/${name}.py" ] || fail "missing $SKILL_DIR/${name}.py"
done

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing usage scripts"
    exit 1
fi

# --- criterion: USAGE_FIXTURE is echoed back verbatim, one line, for all three ---
for name in usage-claudecli usage-minimaxcli usage-qwencli; do
    fixture="$TMP_WORK/${name}-fixture.json"
    echo '{"provider":"fixture-test","five_hour_remaining_pct":42,"weekly_remaining_pct":10,"effective_remaining_pct":10,"available":true}' > "$fixture"
    out="$(USAGE_FIXTURE="$fixture" uv -q run "$SKILL_DIR/${name}.py" 2>"$TMP_WORK/${name}-fixture-stderr.txt")"
    rc=$?
    expected="$(cat "$fixture")"
    if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ] && [ ! -s "$TMP_WORK/${name}-fixture-stderr.txt" ]; then
        pass "${name}.py echoes USAGE_FIXTURE verbatim with a clean exit"
    else
        fail "${name}.py did not echo USAGE_FIXTURE verbatim (rc=$rc out='$out')"
    fi
done

# --- criterion: usage-qwencli.py QWEN_HEALTH_CMD=true -> effective 100, =false -> 0 ---
out="$(QWEN_HEALTH_CMD=true uv -q run "$SKILL_DIR/usage-qwencli.py" 2>"$TMP_WORK/qwen-up-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"effective_remaining_pct": *100' && printf '%s' "$out" | grep -q '"available": *true' && [ ! -s "$TMP_WORK/qwen-up-stderr.txt" ]; then
    pass "usage-qwencli.py QWEN_HEALTH_CMD=true reports effective_remaining_pct 100 / available true"
else
    fail "usage-qwencli.py QWEN_HEALTH_CMD=true did not report 100/true (rc=$rc out='$out')"
fi

out="$(QWEN_HEALTH_CMD=false uv -q run "$SKILL_DIR/usage-qwencli.py" 2>"$TMP_WORK/qwen-down-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"effective_remaining_pct": *0' && printf '%s' "$out" | grep -q '"available": *false' && [ ! -s "$TMP_WORK/qwen-down-stderr.txt" ]; then
    pass "usage-qwencli.py QWEN_HEALTH_CMD=false reports effective_remaining_pct 0 / available false"
else
    fail "usage-qwencli.py QWEN_HEALTH_CMD=false did not report 0/false (rc=$rc out='$out')"
fi

# --- criterion: no data source (fake HOME) -> usage-claudecli.py exits 0 with available:false ---
FAKE_HOME="$TMP_WORK/fakehome"
mkdir -p "$FAKE_HOME"
out="$(HOME="$FAKE_HOME" uv -q run "$SKILL_DIR/usage-claudecli.py" 2>"$TMP_WORK/claude-nohome-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"available": *false' && [ ! -s "$TMP_WORK/claude-nohome-stderr.txt" ]; then
    pass "usage-claudecli.py exits 0 with available:false when no data source exists (fake HOME)"
else
    fail "usage-claudecli.py did not degrade gracefully with a fake HOME (rc=$rc out='$out')"
fi

# --- same graceful-degradation check for minimaxcli (no mmx on PATH, fake HOME/cache) ---
# Strip any directory that has a real `mmx` on it (this dev machine has one
# at ~/.local/bin/mmx) so this test can't slip through to a real network
# call; keep everything else (including uv's own directory) intact.
NO_MMX_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | while read -r d; do
    [ -n "$d" ] && [ ! -x "$d/mmx" ] && printf '%s\n' "$d"
done | paste -sd: -)"
out="$(HOME="$FAKE_HOME" PATH="$NO_MMX_PATH" uv -q run "$SKILL_DIR/usage-minimaxcli.py" 2>"$TMP_WORK/minimax-nohome-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"available": *false' && [ ! -s "$TMP_WORK/minimax-nohome-stderr.txt" ]; then
    pass "usage-minimaxcli.py exits 0 with available:false when no data source exists (fake HOME, no mmx)"
else
    fail "usage-minimaxcli.py did not degrade gracefully with a fake HOME (rc=$rc out='$out')"
fi

# --- criterion: all three run via `uv -q run` (PEP-723 valid) - already exercised above,
#     but confirm exit codes explicitly one more time without fixtures/env tricks other
#     than what's needed to avoid real network/API calls ---
for name in usage-claudecli usage-minimaxcli; do
    HOME="$FAKE_HOME" uv -q run "$SKILL_DIR/${name}.py" > /dev/null 2>"$TMP_WORK/${name}-run-stderr.txt"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass "${name}.py runs cleanly via 'uv -q run' (PEP-723 valid)"
    else
        fail "${name}.py failed to run via 'uv -q run' (rc=$rc)"
    fi
done
QWEN_HEALTH_CMD=true uv -q run "$SKILL_DIR/usage-qwencli.py" > /dev/null 2>"$TMP_WORK/qwen-run-stderr.txt"
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "usage-qwencli.py runs cleanly via 'uv -q run' (PEP-723 valid)"
else
    fail "usage-qwencli.py failed to run via 'uv -q run' (rc=$rc)"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-8 acceptance checks passed."
    exit 0
else
    echo "One or more issue-8 acceptance checks failed."
    exit 1
fi
