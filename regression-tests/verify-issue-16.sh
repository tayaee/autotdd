#!/usr/bin/env bash
# Verifies issue-16: autofix/autodev dispatch — real execution, success
# judgment, failure handling. Uses fixture repo + lib/fake-wrapper.sh only.
# No real autotdd calls, no PATH injection: the engine must resolve the
# wrapper as `bash $AUTOQAFIX_WRAPPER_DIR/<name>.sh` on its own (A-3).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
AUTOFIX_PY="$SKILL_DIR/autofix.py"

FAIL=0
CLEANUP=()

cleanup() {
    for d in "${CLEANUP[@]:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}
pass() {
    echo "PASS: $1"
}

# -- pre-condition: autofix.py exists ----------------------------------------
if [ ! -f "$AUTOFIX_PY" ]; then
    fail "missing $AUTOFIX_PY"
    exit 1
fi
pass "autofix.py exists"

# R-2 regression gate: the engine must not know about the fake wrapper's
# test contract.
if grep -q "FAKE_TARGET" "$AUTOFIX_PY"; then
    fail "autofix.py still injects/knows FAKE_TARGET (R-2 test hook)"
else
    pass "no FAKE_TARGET test hook in autofix.py (R-2)"
fi

# -- helpers -----------------------------------------------------------------
clone_id_of() {
    echo -n "$1" | sha1sum | cut -c1-12
}

# make_fixture <dir>: bare origin + work clone with issues/, main branch.
make_fixture() {
    local base="$1"
    mkdir -p "$base/origin" "$base/work" "$base/fake"
    git init -q --bare "$base/origin"
    git -C "$base/work" init -q -b main
    git -C "$base/work" remote add origin "$base/origin"
    mkdir -p "$base/work/issues"
    # lib/fake-wrapper.sh serves as the claudecli wrapper.
    cp "$LIB/fake-wrapper.sh" "$base/fake/claudecli.sh"
    chmod +x "$base/fake/claudecli.sh"
}

add_item() {
    local work="$1" name="$2" title="$3"
    cat > "$work/issues/$name.md" <<ITEMEOF
# $name: $title
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
$title
ITEMEOF
}

commit_push() {
    local work="$1"
    git -C "$work" add -A
    git -C "$work" commit -q -m "initial"
    git -C "$work" push -q origin main
}

# run_autofix <work> <fake_dir> <output_file> [extra_env]
run_autofix() {
    local fixture_work="$1"
    local fake_wrapper_dir="$2"
    local output_file="$3"
    local extra_env="${4:-}"

    # Pre-create the state dir parent (ensure_worktree mkdirs the rest)
    # and register it for cleanup (B-4: no ~/.cache accumulation).
    local cid
    cid="$(clone_id_of "$fixture_work")"
    local state_dir="$HOME/.cache/autoqafix/$cid"
    mkdir -p "$state_dir"
    CLEANUP+=("$state_dir")

    export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
    export AUTOQAFIX_WRAPPER="claudecli"

    if [ -n "$extra_env" ]; then
        eval "export $extra_env"
    fi

    python3 "$AUTOFIX_PY" --repo "$fixture_work" --stream autofix > "$output_file" 2>&1
}

# B-1: the untracked-dummy check only means something when the file exists
# BEFORE the engine runs.
plant_dummy() {
    echo "human-main-tree-untouched" > "$1/UNTRACKED_DUMMY"
}
check_dummy() {
    local work="$1" label="$2"
    if [ "$(cat "$work/UNTRACKED_DUMMY" 2>/dev/null)" = "human-main-tree-untouched" ]; then
        pass "$label: UNTRACKED_DUMMY unchanged"
    else
        fail "$label: UNTRACKED_DUMMY altered or missing"
    fi
}

# ============================================================================
# TEST 1: FAKE_MODE=archive → success, FIXED=1
# ============================================================================
echo ""
echo "=== TEST 1: FAKE_MODE=archive ==="

T1="$(mktemp -d)"
CLEANUP+=("$T1")
make_fixture "$T1"
add_item "$T1/work" "autofix-1" "archive test"
commit_push "$T1/work"
plant_dummy "$T1/work"
T1_OUT="$T1/out.log"

FAKE_MODE=archive run_autofix "$T1/work" "$T1/fake" "$T1_OUT"

if grep -q "FIXED=1" "$T1_OUT"; then
    pass "TEST 1: FIXED=1"
else
    fail "TEST 1: expected FIXED=1, got: $(grep FIXED "$T1_OUT" || echo '(no output)')"
fi

if git -C "$T1/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/archive/.*/autofix-1.md$"; then
    pass "TEST 1: item archived in origin"
else
    fail "TEST 1: item not archived in origin"
fi

if ! git -C "$T1/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/autofix-1.md$"; then
    pass "TEST 1: item removed from issues/"
else
    fail "TEST 1: item still in issues/"
fi

check_dummy "$T1/work" "TEST 1"

# ============================================================================
# TEST 2: FAKE_MODE=fail → __STATE-agent-failed file with 실패 기록
# ============================================================================
echo ""
echo "=== TEST 2: FAKE_MODE=fail ==="

T2="$(mktemp -d)"
CLEANUP+=("$T2")
make_fixture "$T2"
add_item "$T2/work" "autofix-1" "fail test"
commit_push "$T2/work"
T2_OUT="$T2/out.log"

FAKE_MODE=fail run_autofix "$T2/work" "$T2/fake" "$T2_OUT"

if grep -q "FIXED=0" "$T2_OUT"; then
    pass "TEST 2: FIXED=0"
else
    fail "TEST 2: expected FIXED=0, got: $(grep FIXED "$T2_OUT" || echo '(no output)')"
fi

AGENT_FAILED="$(git -C "$T2/origin" ls-tree -r main --name-only 2>/dev/null | grep '__STATE-agent-failed\.md$' | head -n1)"
if [ -n "$AGENT_FAILED" ]; then
    pass "TEST 2: __STATE-agent-failed file exists in origin"
else
    fail "TEST 2: __STATE-agent-failed file not found in origin"
fi

if [ -n "$AGENT_FAILED" ]; then
    if git -C "$T2/origin" show "main:$AGENT_FAILED" 2>/dev/null | grep -q "## agent 실패 기록"; then
        pass "TEST 2: ## agent 실패 기록 section exists"
    else
        fail "TEST 2: ## agent 실패 기록 section missing"
    fi

    if git -C "$T2/origin" show "main:$AGENT_FAILED" 2>/dev/null | grep -q "claudecli"; then
        pass "TEST 2: wrapper name in 실패 기록"
    else
        fail "TEST 2: wrapper name missing from 실패 기록"
    fi
fi

# ============================================================================
# TEST 3: FAKE_MODE=hang + AUTOQAFIX_IMPL_TIMEOUT=3 → timeout failure
# ============================================================================
echo ""
echo "=== TEST 3: FAKE_MODE=hang + timeout ==="

T3="$(mktemp -d)"
CLEANUP+=("$T3")
make_fixture "$T3"
add_item "$T3/work" "autofix-1" "hang + timeout test"
commit_push "$T3/work"
T3_OUT="$T3/out.log"

# 613: unusual duration so the zombie pgrep below can't hit unrelated
# processes (B-4).
T3_START="$(date +%s)"
FAKE_MODE=hang run_autofix "$T3/work" "$T3/fake" "$T3_OUT" \
    "AUTOQAFIX_IMPL_TIMEOUT=3 FAKE_HANG_SLEEP=613"
T3_ELAPSED=$(( $(date +%s) - T3_START ))

if grep -q "FIXED=0" "$T3_OUT"; then
    pass "TEST 3: FIXED=0"
else
    fail "TEST 3: expected FIXED=0, got: $(grep FIXED "$T3_OUT" || echo '(no output)')"
fi

# Timeout is 3s; unconditional group SIGKILL means no multi-second grace
# tail. Allow git/python overhead but reject the old +5s escalation path.
if [ "$T3_ELAPSED" -le 8 ]; then
    pass "TEST 3: finished in ${T3_ELAPSED}s (~3s timeout honored)"
else
    fail "TEST 3: took ${T3_ELAPSED}s — timeout not honored"
fi

AGENT_FAILED3="$(git -C "$T3/origin" ls-tree -r main --name-only 2>/dev/null | grep '__STATE-agent-failed\.md$' | head -n1)"
if [ -n "$AGENT_FAILED3" ]; then
    pass "TEST 3: __STATE-agent-failed file exists"
else
    fail "TEST 3: __STATE-agent-failed file not found"
fi

if [ -n "$AGENT_FAILED3" ]; then
    if git -C "$T3/origin" show "main:$AGENT_FAILED3" 2>/dev/null | grep -q "## agent 실패 기록"; then
        pass "TEST 3: ## agent 실패 기록 exists"
    else
        fail "TEST 3: ## agent 실패 기록 missing"
    fi

    if git -C "$T3/origin" show "main:$AGENT_FAILED3" 2>/dev/null | grep -q "timeout (3s)"; then
        pass "TEST 3: timeout (3s) in 실패 기록 (int seconds, no float)"
    else
        fail "TEST 3: 'timeout (3s)' not in 실패 기록"
    fi
fi

sleep 1
if pgrep -f "sleep 613" > /dev/null 2>&1; then
    fail "TEST 3: zombie 'sleep 613' process survived the group kill"
else
    pass "TEST 3: no zombie processes"
fi

# extra_env exports persist in this shell — don't leak them into TEST 4+.
unset AUTOQAFIX_IMPL_TIMEOUT FAKE_HANG_SLEEP

# ============================================================================
# TEST 4: fail item FIRST, then archive item → continuation after failure
# (B-2: the fail must come first for "실패 항목 뒤에도 다음 항목 처리가
# 계속된다" to actually be exercised)
# ============================================================================
echo ""
echo "=== TEST 4: fail-first + archive mixed ==="

T4="$(mktemp -d)"
CLEANUP+=("$T4")
make_fixture "$T4"
add_item "$T4/work" "autofix-1" "fail item"
add_item "$T4/work" "autofix-2" "archive item"
commit_push "$T4/work"
plant_dummy "$T4/work"
T4_OUT="$T4/out.log"

FAKE_MODE_MAP="autofix-1=fail,autofix-2=archive" run_autofix "$T4/work" "$T4/fake" "$T4_OUT"

if grep -q "FIXED=1" "$T4_OUT"; then
    pass "TEST 4: FIXED=1"
else
    fail "TEST 4: expected FIXED=1, got: $(grep FIXED "$T4_OUT" || echo '(no output)')"
fi

if git -C "$T4/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/autofix-1__STATE-agent-failed.md$"; then
    pass "TEST 4: autofix-1 is the __STATE-agent-failed item"
else
    fail "TEST 4: autofix-1__STATE-agent-failed.md not in origin"
fi

if git -C "$T4/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/archive/.*/autofix-2.md$"; then
    pass "TEST 4: autofix-2 archived AFTER autofix-1 failed (continuation)"
else
    fail "TEST 4: autofix-2 not archived — engine stopped after the failure"
fi

AGENT_FAILED_COUNT="$(git -C "$T4/origin" ls-tree -r main --name-only 2>/dev/null | grep -c '__STATE-agent-failed\.md$' || true)"
if [ "$AGENT_FAILED_COUNT" -eq 1 ]; then
    pass "TEST 4: exactly one __STATE-agent-failed in origin"
else
    fail "TEST 4: expected 1 __STATE-agent-failed, got $AGENT_FAILED_COUNT"
fi

check_dummy "$T4/work" "TEST 4"

# ============================================================================
# TEST 5: wrapper archives+pushes then exits 1 → still success (A-2)
# ============================================================================
echo ""
echo "=== TEST 5: archive_fail (archive+push then exit 1) ==="

T5="$(mktemp -d)"
CLEANUP+=("$T5")
make_fixture "$T5"
add_item "$T5/work" "autofix-1" "archive then die"
commit_push "$T5/work"
T5_OUT="$T5/out.log"

FAKE_MODE=archive_fail run_autofix "$T5/work" "$T5/fake" "$T5_OUT"
T5_RC=$?

if [ "$T5_RC" -eq 0 ]; then
    pass "TEST 5: engine exit 0 (no crash on archive+exit!=0)"
else
    fail "TEST 5: engine crashed (rc=$T5_RC): $(tail -n 5 "$T5_OUT")"
fi

if grep -q "FIXED=1" "$T5_OUT"; then
    pass "TEST 5: FIXED=1 (success judged by archive, not exit code)"
else
    fail "TEST 5: expected FIXED=1, got: $(grep FIXED "$T5_OUT" || echo '(no output)')"
fi

if ! git -C "$T5/origin" ls-tree -r main --name-only 2>/dev/null | grep -q '__STATE-agent-failed\.md$'; then
    pass "TEST 5: no spurious __STATE-agent-failed for an archived item"
else
    fail "TEST 5: __STATE-agent-failed recorded despite successful archive"
fi

# ============================================================================
# TEST 6: wrapper leaves an unpushed partial commit and exits 1 →
# origin/main must NOT be polluted (R-1: reset --hard recovery)
# ============================================================================
echo ""
echo "=== TEST 6: dirty_fail (partial commit left in worktree) ==="

T6="$(mktemp -d)"
CLEANUP+=("$T6")
make_fixture "$T6"
add_item "$T6/work" "autofix-1" "dirty fail item"
commit_push "$T6/work"
T6_OUT="$T6/out.log"

FAKE_MODE=dirty_fail run_autofix "$T6/work" "$T6/fake" "$T6_OUT"
T6_RC=$?

if [ "$T6_RC" -eq 0 ]; then
    pass "TEST 6: engine exit 0"
else
    fail "TEST 6: engine crashed (rc=$T6_RC): $(tail -n 5 "$T6_OUT")"
fi

if git -C "$T6/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^junk.txt$"; then
    fail "TEST 6: wrapper junk commit leaked into origin/main (R-1)"
else
    pass "TEST 6: origin/main free of wrapper junk (reset --hard recovery)"
fi

if git -C "$T6/origin" log main --format=%s 2>/dev/null | grep -q "wip: partial work"; then
    fail "TEST 6: partial-work commit reached origin/main history (R-1)"
else
    pass "TEST 6: no partial-work commit in origin/main history"
fi

if git -C "$T6/origin" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/autofix-1__STATE-agent-failed.md$"; then
    pass "TEST 6: __STATE-agent-failed recorded on origin"
else
    fail "TEST 6: __STATE-agent-failed missing from origin"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED" >&2
fi

exit "$FAIL"
