#!/usr/bin/env bash
# Verifies issue-9 acceptance criteria: select-llm.py's effective-remaining
# selection matrix (CONTEXT.md "유효 잔여율").
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
SCRIPT="$SKILL_DIR/select-llm.py"

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

command -v uv > /dev/null 2>&1 || { echo "FAIL: uv not found on PATH, cannot verify select-llm.py" >&2; exit 1; }

if [ ! -f "$SCRIPT" ]; then
    fail "missing $SCRIPT"
    echo "aborting further checks: select-llm.py not found"
    exit 1
fi

fixture() {
    # fixture <path> <five_hour_remaining_pct> <weekly_remaining_pct> <effective_remaining_pct> <available>
    local path="$1" five="$2" weekly="$3" eff="$4" avail="$5"
    printf '{"provider":"x","five_hour_remaining_pct":%s,"weekly_remaining_pct":%s,"effective_remaining_pct":%s,"available":%s}\n' \
        "$five" "$weekly" "$eff" "$avail" > "$path"
}

# --- Case 1: claudecli(5h 80, 주간 60 -> 유효 60) vs minimaxcli(5h 70, 주간 90 -> 유효 70)
#     -> 유효 잔여율이 큰 minimaxcli (70 > 60, 둘 다 paid+eligible) ---
c1_claude="$TMP_WORK/c1-claude.json"; fixture "$c1_claude" 80 60 60 true
c1_minimax="$TMP_WORK/c1-minimax.json"; fixture "$c1_minimax" 70 90 70 true
out="$(AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="cat $c1_claude" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="cat $c1_minimax" \
    uv -q run "$SCRIPT" 2>"$TMP_WORK/c1-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "minimaxcli" ]; then
    pass "case 1: higher effective (minimaxcli 70 > claudecli 60) wins"
else
    fail "case 1: expected 'minimaxcli' exit 0, got out='$out' rc=$rc"
fi

# --- Case 2: claudecli(90,40 -> 유효 40) vs minimaxcli(45,80 -> 유효 45)
#     -> 둘 다 <50 (paid 부적격) -> qwen UP -> qwencli ---
c2_claude="$TMP_WORK/c2-claude.json"; fixture "$c2_claude" 90 40 40 true
c2_minimax="$TMP_WORK/c2-minimax.json"; fixture "$c2_minimax" 45 80 45 true
c2_qwen="$TMP_WORK/c2-qwen.json"; fixture "$c2_qwen" 100 100 100 true
out="$(AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid,qwencli:local" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="cat $c2_claude" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="cat $c2_minimax" \
    AUTOQAFIX_USAGE_CMD_QWENCLI="cat $c2_qwen" \
    uv -q run "$SCRIPT" 2>"$TMP_WORK/c2-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "qwencli" ]; then
    pass "case 2: both paid ineligible (<50) falls back to local qwencli (UP)"
else
    fail "case 2: expected 'qwencli' exit 0, got out='$out' rc=$rc"
fi

# --- Case 3: 둘 다 유효 55로 동률 -> 목록 앞쪽인 claudecli ---
c3_claude="$TMP_WORK/c3-claude.json"; fixture "$c3_claude" 55 55 55 true
c3_minimax="$TMP_WORK/c3-minimax.json"; fixture "$c3_minimax" 55 55 55 true
out="$(AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="cat $c3_claude" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="cat $c3_minimax" \
    uv -q run "$SCRIPT" 2>"$TMP_WORK/c3-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "claudecli" ]; then
    pass "case 3: tie at effective=55 breaks toward the earlier-listed claudecli"
else
    fail "case 3: expected 'claudecli' exit 0, got out='$out' rc=$rc"
fi

# --- Case 4: 전부 불가 -> none + exit 2 ---
c4_claude="$TMP_WORK/c4-claude.json"; fixture "$c4_claude" 0 0 0 false
c4_minimax="$TMP_WORK/c4-minimax.json"; fixture "$c4_minimax" 0 0 0 false
c4_qwen="$TMP_WORK/c4-qwen.json"; fixture "$c4_qwen" 0 0 0 false
out="$(AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid,qwencli:local" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="cat $c4_claude" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="cat $c4_minimax" \
    AUTOQAFIX_USAGE_CMD_QWENCLI="cat $c4_qwen" \
    uv -q run "$SCRIPT" 2>"$TMP_WORK/c4-stderr.txt")"
rc=$?
if [ "$rc" -eq 2 ] && [ "$out" = "none" ]; then
    pass "case 4: everything unavailable -> 'none' + exit 2"
else
    fail "case 4: expected 'none' exit 2, got out='$out' rc=$rc"
fi

# --- Case 5: AUTOQAFIX_WRAPPER=qwencli -> usage 조회 없이 그 값 그대로,
#     usage 명령이 전혀 실행되지 않았는지도 확인 (실행됐다면 존재하지 않는
#     커맨드라 에러가 stderr에 찍히거나 실패했을 것) ---
out="$(AUTOQAFIX_WRAPPER=qwencli \
    AUTOQAFIX_USAGE_CMD_QWENCLI="/nonexistent/should-not-run" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="/nonexistent/should-not-run" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="/nonexistent/should-not-run" \
    uv -q run "$SCRIPT" 2>"$TMP_WORK/c5-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "qwencli" ] && [ ! -s "$TMP_WORK/c5-stderr.txt" ]; then
    pass "case 5: AUTOQAFIX_WRAPPER=qwencli short-circuits usage lookup entirely"
else
    fail "case 5: expected 'qwencli' exit 0 with no stderr, got out='$out' rc=$rc stderr='$(cat "$TMP_WORK/c5-stderr.txt" 2>/dev/null)'"
fi

# --- bonus: --explain prints something to stderr without touching stdout's single line ---
out="$(AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid" \
    AUTOQAFIX_USAGE_CMD_CLAUDECLI="cat $c1_claude" \
    AUTOQAFIX_USAGE_CMD_MINIMAXCLI="cat $c1_minimax" \
    uv -q run "$SCRIPT" --explain 2>"$TMP_WORK/explain-stderr.txt")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "minimaxcli" ] && [ -s "$TMP_WORK/explain-stderr.txt" ]; then
    pass "--explain keeps stdout to the single selected name and writes the rationale to stderr"
else
    fail "--explain did not behave as expected (out='$out' rc=$rc)"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-9 acceptance checks passed."
    exit 0
else
    echo "One or more issue-9 acceptance checks failed."
    exit 1
fi
