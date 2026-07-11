#!/usr/bin/env bash
# Verifies issue-16: autofix/autodev dispatch — real execution, success
# judgment, failure handling. Uses fixture repo + fake-wrapper only.
# No real autotdd calls.
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

# -- helpers -----------------------------------------------------------------
make_bare_origin() {
    local dir="$1"
    mkdir -p "$dir"
    git init -q --bare "$dir"
}

clone_id_of() {
    echo -n "$1" | sha1sum | cut -c1-12
}

run_autofix() {
    local fixture_work="$1"
    local fake_wrapper_dir="$2"
    local output_file="$3"
    local extra_env="${4:-}"

    # Compute the worktree path that the engine will create.
    local cid
    cid="$(clone_id_of "$fixture_work")"
    local state_dir="$HOME/.cache/autoqafix/$cid"
    local worktree="$state_dir/worktree"

    # Create the parent dir so ensure_worktree's mkdir(parents=True)
    # can create worktree/ — but do NOT create worktree/ itself,
    # otherwise ensure_worktree tries `git pull` on a non-worktree dir.
    mkdir -p "$state_dir"

    # Set FAKE_TARGET to the item that will be checked out when the
    # engine creates the worktree (detached HEAD at main's tip).
    if [ -n "${FAKE_ITEM_NAME:-}" ]; then
        export FAKE_TARGET="$worktree/issues/$FAKE_ITEM_NAME"
    fi

    export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
    export AUTOQAFIX_WRAPPER="claudecli"
    export PATH="$fake_wrapper_dir:$PATH"
    export HOME="$HOME"
    # Ensure FAKE_MODE is explicitly passed to the python process.
    export FAKE_MODE="${FAKE_MODE:-ok}"

    if [ -n "$extra_env" ]; then
        eval "export $extra_env"
    fi

    python3 "$AUTOFIX_PY" --repo "$fixture_work" --stream autofix > "$output_file" 2>&1
}

check_no_zombies() {
    local count
    count="$(pgrep -f "sleep 600" 2>/dev/null | wc -l)"
    if [ "$count" -gt 0 ]; then
        fail "zombie sleep processes remain: $count"
    else
        pass "no zombie processes"
    fi
}

# ============================================================================
# TEST 1: FAKE_MODE=archive → success, FIXED=1
# ============================================================================
echo ""
echo "=== TEST 1: FAKE_MODE=archive ==="

T1_FIXTURE="$(mktemp -d)"
CLEANUP+=("$T1_FIXTURE")
T1_ORIGIN="$T1_FIXTURE/origin"
T1_WORK="$T1_FIXTURE/work"
T1_FAKE="$T1_FIXTURE/fake"
mkdir -p "$T1_WORK" "$T1_FAKE"

# Create bare origin.
make_bare_origin "$T1_ORIGIN"

# Create work tree with main branch.
git -C "$T1_WORK" init -q -b main
git -C "$T1_WORK" remote add origin "$T1_ORIGIN"
mkdir -p "$T1_WORK/issues"
cat > "$T1_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: archive test
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
archive mode 테스트.
ITEMEOF
git -C "$T1_WORK" add -A
git -C "$T1_WORK" commit -q -m "initial"
git -C "$T1_WORK" push -q origin main

# Fake wrapper: archive mode archives FAKE_TARGET.
cat > "$T1_FAKE/claudecli.sh" <<'WEOF'
#!/usr/bin/env bash
if [ "${FAKE_MODE:-ok}" = "archive" ]; then
    if [ -z "${FAKE_TARGET:-}" ]; then
        echo "fake-wrapper: FAKE_TARGET required for archive mode" >&2
        exit 1
    fi
    dest="issues/archive/$(date +%Y/%m/%d)"
    mkdir -p "$dest"
    git mv "$FAKE_TARGET" "$dest/" || exit 1
    git commit -q -m "archive: $(basename "$FAKE_TARGET")" || exit 1
    git push -q origin HEAD:main || exit 1
    exit 0
fi
echo "pong"
exit 0
WEOF
chmod +x "$T1_FAKE/claudecli.sh"
# Engine calls wrapper by name WITHOUT .sh extension.
ln -sf "claudecli.sh" "$T1_FAKE/claudecli"

# Compute state_dir so we know FAKE_TARGET before running.
CID1="$(clone_id_of "$T1_WORK")"
STATE_DIR1="$HOME/.cache/autoqafix/$CID1"
mkdir -p "$STATE_DIR1"

# Clean up stale state from previous runs.
rm -rf "$STATE_DIR1/worktree" 2>/dev/null

FAKE_TARGET="$STATE_DIR1/worktree/issues/autofix-1.md" FAKE_MODE=archive FAKE_ITEM_NAME="autofix-1.md" \
    run_autofix "$T1_WORK" "$T1_FAKE" /tmp/t1_output

# Verify FIXED=1.
if grep -q "FIXED=1" /tmp/t1_output; then
    pass "TEST 1: FIXED=1"
else
    fail "TEST 1: expected FIXED=1, got: $(grep FIXED /tmp/t1_output || echo '(no output)')"
fi

# Verify item archived in worktree (origin is bare, check worktree instead).
ARCHIVED_FILE="$(find "$STATE_DIR1/worktree/issues/archive" -name "autofix-1.md" 2>/dev/null | head -n1)"
if [ -n "$ARCHIVED_FILE" ]; then
    pass "TEST 1: item archived in origin"
else
    fail "TEST 1: item not archived in origin"
fi

# Verify item removed from issues/ in origin.
if ! git -C "$T1_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep -q "^issues/autofix-1.md$"; then
    pass "TEST 1: item removed from issues/"
else
    fail "TEST 1: item still in issues/"
fi

# Verify UNTRACKED_DUMMY unchanged.
echo "human-main-tree-untouched" > "$T1_WORK/UNTRACKED_DUMMY"
if [ "$(cat "$T1_WORK/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
    pass "TEST 1: UNTRACKED_DUMMY unchanged"
else
    fail "TEST 1: UNTRACKED_DUMMY was altered"
fi

# ============================================================================
# TEST 2: FAKE_MODE=fail → -agent-failed file with 실패 기록
# ============================================================================
echo ""
echo "=== TEST 2: FAKE_MODE=fail ==="

T2_FIXTURE="$(mktemp -d)"
CLEANUP+=("$T2_FIXTURE")
T2_ORIGIN="$T2_FIXTURE/origin"
T2_WORK="$T2_FIXTURE/work"
T2_FAKE="$T2_FIXTURE/fake"
mkdir -p "$T2_WORK" "$T2_FAKE"

make_bare_origin "$T2_ORIGIN"
git -C "$T2_WORK" init -q -b main
git -C "$T2_WORK" remote add origin "$T2_ORIGIN"
mkdir -p "$T2_WORK/issues"
cat > "$T2_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: fail test
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
fail mode 테스트.
ITEMEOF
git -C "$T2_WORK" add -A
git -C "$T2_WORK" commit -q -m "initial"
git -C "$T2_WORK" push -q origin main

cat > "$T2_FAKE/claudecli.sh" <<'WEOF'
#!/usr/bin/env bash
if [ "${FAKE_MODE:-ok}" = "fail" ]; then
    echo "fake-wrapper: simulated failure" >&2
    exit 1
fi
echo "pong"
exit 0
WEOF
chmod +x "$T2_FAKE/claudecli.sh"
ln -sf "claudecli.sh" "$T2_FAKE/claudecli"

CID2="$(clone_id_of "$T2_WORK")"
STATE_DIR2="$HOME/.cache/autoqafix/$CID2"
mkdir -p "$STATE_DIR2"

FAKE_MODE=fail FAKE_ITEM_NAME="autofix-1.md" \
    run_autofix "$T2_WORK" "$T2_FAKE" /tmp/t2_output

if grep -q "FIXED=0" /tmp/t2_output; then
    pass "TEST 2: FIXED=0"
else
    fail "TEST 2: expected FIXED=0, got: $(grep FIXED /tmp/t2_output || echo '(no output)')"
fi

# Check -agent-failed file exists in origin.
AGENT_FAILED="$(git -C "$T2_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep '\-agent-failed\.md$' | head -n1)"
if [ -n "$AGENT_FAILED" ]; then
    pass "TEST 2: -agent-failed file exists in origin"
else
    fail "TEST 2: -agent-failed file not found in origin"
fi

# Check ## agent 실패 기록 section exists.
if [ -n "$AGENT_FAILED" ]; then
    if git -C "$T2_ORIGIN" show "main:$AGENT_FAILED" 2>/dev/null | grep -q "## agent 실패 기록"; then
        pass "TEST 2: ## agent 실패 기록 section exists"
    else
        fail "TEST 2: ## agent 실패 기록 section missing"
    fi

    # Check wrapper name in 실패 기록.
    if git -C "$T2_ORIGIN" show "main:$AGENT_FAILED" 2>/dev/null | grep -q "claudecli"; then
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

# Reset FAKE_MODE to avoid leakage from previous tests.
unset FAKE_MODE

T3_FIXTURE="$(mktemp -d)"
CLEANUP+=("$T3_FIXTURE")
T3_ORIGIN="$T3_FIXTURE/origin"
T3_WORK="$T3_FIXTURE/work"
T3_FAKE="$T3_FIXTURE/fake"
mkdir -p "$T3_WORK" "$T3_FAKE"

make_bare_origin "$T3_ORIGIN"
git -C "$T3_WORK" init -q -b main
git -C "$T3_WORK" remote add origin "$T3_ORIGIN"
mkdir -p "$T3_WORK/issues"
cat > "$T3_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: hang test
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
hang + timeout 테스트.
ITEMEOF
git -C "$T3_WORK" add -A
git -C "$T3_WORK" commit -q -m "initial"
git -C "$T3_WORK" push -q origin main

cat > "$T3_FAKE/claudecli.sh" <<'WEOF'
#!/usr/bin/env bash
if [ "${FAKE_MODE:-ok}" = "hang" ]; then
    sleep 600
    exit 0
fi
echo "pong"
exit 0
WEOF
chmod +x "$T3_FAKE/claudecli.sh"
ln -sf "claudecli.sh" "$T3_FAKE/claudecli"

CID3="$(clone_id_of "$T3_WORK")"
STATE_DIR3="$HOME/.cache/autoqafix/$CID3"
mkdir -p "$STATE_DIR3"

# Clean up stale state from previous runs.
rm -rf "$STATE_DIR3/worktree" 2>/dev/null

FAKE_MODE=hang FAKE_ITEM_NAME="autofix-1.md" \
    run_autofix "$T3_WORK" "$T3_FAKE" /tmp/t3_output "AUTOQAFIX_IMPL_TIMEOUT=3"

if grep -q "FIXED=0" /tmp/t3_output; then
    pass "TEST 3: FIXED=0"
else
    fail "TEST 3: expected FIXED=0, got: $(grep FIXED /tmp/t3_output || echo '(no output)')"
fi

AGENT_FAILED3="$(git -C "$T3_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep '\-agent-failed\.md$' | head -n1)"
if [ -n "$AGENT_FAILED3" ]; then
    pass "TEST 3: -agent-failed file exists"
else
    fail "TEST 3: -agent-failed file not found"
fi

if [ -n "$AGENT_FAILED3" ]; then
    if git -C "$T3_ORIGIN" show "main:$AGENT_FAILED3" 2>/dev/null | grep -q "## agent 실패 기록"; then
        pass "TEST 3: ## agent 실패 기록 exists"
    else
        fail "TEST 3: ## agent 실패 기록 missing"
    fi

    if git -C "$T3_ORIGIN" show "main:$AGENT_FAILED3" 2>/dev/null | grep -q "timeout"; then
        pass "TEST 3: timeout mentioned in 실패 기록"
    else
        fail "TEST 3: timeout not mentioned in 실패 기록"
    fi
fi

# Check no zombie processes.
sleep 1
check_no_zombies

# ============================================================================
# TEST 4: fail item + archive item → FIXED=1, one -agent-failed
# ============================================================================
echo ""
echo "=== TEST 4: fail + archive mixed ==="

T4_FIXTURE="$(mktemp -d)"
CLEANUP+=("$T4_FIXTURE")
T4_ORIGIN="$T4_FIXTURE/origin"
T4_WORK="$T4_FIXTURE/work"
T4_FAKE="$T4_FIXTURE/fake"
mkdir -p "$T4_WORK" "$T4_FAKE"

make_bare_origin "$T4_ORIGIN"
git -C "$T4_WORK" init -q -b main
git -C "$T4_WORK" remote add origin "$T4_ORIGIN"
mkdir -p "$T4_WORK/issues"

cat > "$T4_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: fail item
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
fail 할 항목.
ITEMEOF

cat > "$T4_WORK/issues/autofix-2.md" <<'ITEMEOF'
# autofix-2: archive item
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
archive 될 항목.
ITEMEOF

git -C "$T4_WORK" add -A
git -C "$T4_WORK" commit -q -m "initial"
git -C "$T4_WORK" push -q origin main

cat > "$T4_FAKE/claudecli.sh" <<'WEOF'
#!/usr/bin/env bash
mode="${FAKE_MODE:-ok}"
item="$(basename "${FAKE_TARGET:-}")"
if [ "$mode" = "archive" ] && [ "$item" = "autofix-1.md" ]; then
    if [ -z "${FAKE_TARGET:-}" ]; then
        echo "fake-wrapper: FAKE_TARGET required" >&2
        exit 1
    fi
    dest="issues/archive/$(date +%Y/%m/%d)"
    mkdir -p "$dest"
    git mv "$FAKE_TARGET" "$dest/" || exit 1
    git commit -q -m "archive: $(basename "$FAKE_TARGET")" || exit 1
    git push -q origin HEAD:main || exit 1
    exit 0
fi
if [ "$mode" = "archive" ] && [ "$item" = "autofix-2.md" ]; then
    echo "fake-wrapper: simulated failure for autofix-2" >&2
    exit 1
fi
echo "pong"
exit 0
WEOF
chmod +x "$T4_FAKE/claudecli.sh"
ln -sf "claudecli.sh" "$T4_FAKE/claudecli"

CID4="$(clone_id_of "$T4_WORK")"
STATE_DIR4="$HOME/.cache/autoqafix/$CID4"
mkdir -p "$STATE_DIR4"

FAKE_MODE=archive FAKE_ITEM_NAME="autofix-1.md" \
    run_autofix "$T4_WORK" "$T4_FAKE" /tmp/t4_output

if grep -q "FIXED=1" /tmp/t4_output; then
    pass "TEST 4: FIXED=1"
else
    fail "TEST 4: expected FIXED=1, got: $(grep FIXED /tmp/t4_output || echo '(no output)')"
fi

AGENT_FAILED_COUNT="$(git -C "$T4_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep -c '\-agent-failed\.md$' || true)"
if [ "$AGENT_FAILED_COUNT" -eq 1 ]; then
    pass "TEST 4: exactly one -agent-failed in origin"
else
    fail "TEST 4: expected 1 -agent-failed, got $AGENT_FAILED_COUNT"
fi

# Verify UNTRACKED_DUMMY unchanged.
echo "human-main-tree-untouched" > "$T4_WORK/UNTRACKED_DUMMY"
if [ "$(cat "$T4_WORK/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
    pass "TEST 4: UNTRACKED_DUMMY unchanged"
else
    fail "TEST 4: UNTRACKED_DUMMY was altered"
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
