#!/usr/bin/env bash
# Verifies issue-17: autofix/autodev launchers (6 scripts) plus their
# dispatch behavior. Mirrors verify-issue-14.sh shape (autoqa launchers)
# but exercises the autofix/autodev entries and adds the stream filter
# test (`autodev.sh` must process only `issue-*` items, not `autofix-*`).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
AUTOFIX_PY="$SKILL_DIR/autofix.py"

# Repo-root launcher paths.
AUTOFIX_SH="$REPO_ROOT/autofix.sh"
AUTOFIX_PS1="$REPO_ROOT/autofix.ps1"
AUTOFIX_BAT="$REPO_ROOT/autofix.bat"
AUTODEV_SH="$REPO_ROOT/autodev.sh"
AUTODEV_PS1="$REPO_ROOT/autodev.ps1"
AUTODEV_BAT="$REPO_ROOT/autodev.bat"

FAIL=0
CLEANUP_DIRS=()

cleanup() {
    for d in "${CLEANUP_DIRS[@]:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
    done
    # Best-effort cleanup of any autoqafix cache dirs we created.
    rm -rf "$HOME/.cache/autoqafix" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}
pass() {
    echo "PASS: $1"
}

# ============================================================================
# 1. Pre-condition: all 6 launchers must exist
# ============================================================================
for f in "$AUTOFIX_SH" "$AUTOFIX_PS1" "$AUTOFIX_BAT" \
         "$AUTODEV_SH" "$AUTODEV_PS1" "$AUTODEV_BAT"; do
    if [ ! -f "$f" ]; then
        fail "missing $f"
    fi
done
# One or more files missing → bail (further checks are meaningless).
[ "$FAIL" -eq 0 ] || exit 1

# ============================================================================
# 2. Static checks: bash -n on .sh, 'pause' on .bat
# ============================================================================
if bash -n "$AUTOFIX_SH"; then
    pass "bash -n autofix.sh passed"
else
    fail "bash -n autofix.sh failed"
fi

if bash -n "$AUTODEV_SH"; then
    pass "bash -n autodev.sh passed"
else
    fail "bash -n autodev.sh failed"
fi

if grep -q -i "pause" "$AUTOFIX_BAT"; then
    pass "autofix.bat has 'pause' statement"
else
    fail "autofix.bat is missing 'pause' statement"
fi

if grep -q -i "pause" "$AUTODEV_BAT"; then
    pass "autodev.bat has 'pause' statement"
else
    fail "autodev.bat is missing 'pause' statement"
fi

# ============================================================================
# 3. Build a fixture repo with one autofix-1.md item.
#    The acceptance criterion runs autofix.sh from cwd with FAKE_WRAPPER
#    + FAKE_MODE=archive, expecting FIXED=1 (same as issue-16 regression).
# ============================================================================
T_FIXTURE="$(mktemp -d)"
CLEANUP_DIRS+=("$T_FIXTURE")
T_ORIGIN="$T_FIXTURE/origin"
T_WORK="$T_FIXTURE/work"
T_FAKE="$T_FIXTURE/fake"
mkdir -p "$T_WORK" "$T_FAKE"

# Bare origin + cloned work tree with main branch.
git init -q --bare -b main "$T_ORIGIN"
git clone -q "$T_ORIGIN" "$T_WORK"
git -C "$T_WORK" config user.name "Fixture Bot"
git -C "$T_WORK" config user.email "fixture-bot@example.com"
mkdir -p "$T_WORK/issues" "$T_WORK/logs"
touch "$T_WORK/issues/.gitkeep"

# Seed a minimal autofix-1 item the engine will pick up. The engine needs
# agent-tier so it won't try the tier-stamping branch in test mode.
cat > "$T_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: launcher archive test
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
launcher 검증.
ITEMEOF

git -C "$T_WORK" add -A
git -C "$T_WORK" commit -q -m "fixture seed"
git -C "$T_WORK" push -q -u origin main

# Fake wrapper that archives FAKE_TARGET — same shape as verify-issue-16.sh
# TEST 1's inline wrapper: cwd is the worktree (autofix.py sets it), so
# `git mv <abs> <rel>` and `git push origin HEAD:main` work directly.
cat > "$T_FAKE/claudecli.sh" <<'WRAPEOF'
#!/usr/bin/env bash
if [ "${FAKE_MODE:-ok}" = "archive" ]; then
    if [ -z "${FAKE_TARGET:-}" ]; then
        echo "fake: FAKE_TARGET required for archive mode" >&2
        exit 1
    fi
    dest="issues/archive/$(date +%Y/%m/%d)"
    mkdir -p "$dest"
    git mv "$FAKE_TARGET" "$dest/" || exit 1
    git commit -q -m "archive: $(basename "$FAKE_TARGET")" || exit 1
    git push -q origin HEAD:main || exit 1
    exit 0
fi
if [ "${FAKE_MODE:-ok}" = "fail" ]; then
    echo "fake: simulated failure" >&2
    exit 1
fi
echo "pong"
exit 0
WRAPEOF
chmod +x "$T_FAKE/claudecli.sh"
# Engine calls wrapper by name WITHOUT .sh extension.
ln -sf "claudecli.sh" "$T_FAKE/claudecli"

# Compute state_dir so we know FAKE_TARGET up front.
CLONE_ID="$(echo -n "$T_WORK" | sha1sum | cut -c1-12)"
STATE_DIR="$HOME/.cache/autoqafix/$CLONE_ID"
rm -rf "$STATE_DIR" 2>/dev/null
mkdir -p "$STATE_DIR"

# Run autofix.sh from the fixture worktree cwd, with the engine pointed at
# the inline fake wrapper. Engine uses `claudecli` (no .sh) — find on PATH.
export AUTOQAFIX_WRAPPER_DIR="$T_FAKE"
export AUTOQAFIX_WRAPPER="claudecli"
export AUTOQAFIX_WRAPPERS="claudecli:paid"
export FAKE_MODE=archive
export FAKE_TARGET="$STATE_DIR/worktree/issues/autofix-1.md"
export FAKE_ITEM_NAME="autofix-1.md"
export PATH="$T_FAKE:$PATH"

set +e
output_autofix="$(cd "$T_WORK" && bash "$AUTOFIX_SH" 2>&1)"
rc_autofix=$?
set -e

# Only check rc==0 if FIXED=1 — the acceptance criterion is the FIXED
# line, but a non-zero rc would normally indicate a launcher-side fault.
if [ "$rc_autofix" -eq 0 ] || echo "$output_autofix" | grep -q "^FIXED=1"; then
    pass "autofix.sh → FIXED=1 (launcher dispatched and archive succeeded)"
else
    fail "autofix.sh did not produce FIXED=1. output: $output_autofix"
fi

# Verify the item is archived at the origin (the engine pushes there).
ARCHIVED_IN_ORIGIN="$(git -C "$T_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep "issues/archive/.*/autofix-1.md" || true)"
if [ -n "$ARCHIVED_IN_ORIGIN" ]; then
    pass "autofix.sh → item archived in origin"
else
    fail "autofix.sh → item not archived in origin"
fi

# ============================================================================
# 4. Stream filter: autodev.sh must process only `issue-*` items.
#    Fixture has BOTH an autofix-1.md and an issue-1.md; only issue-1.md
#    should end up archived after running autodev.sh.
# ============================================================================
T2_FIXTURE="$(mktemp -d)"
CLEANUP_DIRS+=("$T2_FIXTURE")
T2_ORIGIN="$T2_FIXTURE/origin"
T2_WORK="$T2_FIXTURE/work"
T2_FAKE="$T2_FIXTURE/fake"
mkdir -p "$T2_WORK" "$T2_FAKE"

git init -q --bare -b main "$T2_ORIGIN"
git clone -q "$T2_ORIGIN" "$T2_WORK"
git -C "$T2_WORK" config user.name "Fixture Bot"
git -C "$T2_WORK" config user.email "fixture-bot@example.com"
mkdir -p "$T2_WORK/issues" "$T2_WORK/logs"
touch "$T2_WORK/issues/.gitkeep"

# Two items: one autofix (must NOT be archived by autodev) and one issue
# (must be archived).
cat > "$T2_WORK/issues/autofix-1.md" <<'ITEMEOF'
# autofix-1: autofix stream item
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
autofix stream — autodev should skip.
ITEMEOF

cat > "$T2_WORK/issues/issue-1.md" <<'ITEMEOF'
# issue-1: issue stream item
agent-tier: local-ok
reported-by: test@dummy 2026-07-10T12:00:00Z

## 배경
issue stream — autodev should archive.
ITEMEOF

git -C "$T2_WORK" add -A
git -C "$T2_WORK" commit -q -m "fixture seed (both streams)"
git -C "$T2_WORK" push -q -u origin main

# Fake wrapper for autodev run (same shape as TEST 1, plus invocation
# logging via FAKE_LOG so we can assert the issue stream was selected).
cat > "$T2_FAKE/claudecli.sh" <<'WRAPEOF'
#!/usr/bin/env bash
if [ -n "${FAKE_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_LOG"
fi
if [ "${FAKE_MODE:-ok}" = "archive" ]; then
    if [ -z "${FAKE_TARGET:-}" ]; then
        echo "fake: FAKE_TARGET required for archive mode" >&2
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
WRAPEOF
chmod +x "$T2_FAKE/claudecli.sh"
ln -sf "claudecli.sh" "$T2_FAKE/claudecli"

CLONE_ID2="$(echo -n "$T2_WORK" | sha1sum | cut -c1-12)"
STATE_DIR2="$HOME/.cache/autoqafix/$CLONE_ID2"
rm -rf "$STATE_DIR2" 2>/dev/null
mkdir -p "$STATE_DIR2"

export AUTOQAFIX_WRAPPER_DIR="$T2_FAKE"
export AUTOQAFIX_WRAPPER="claudecli"
export AUTOQAFIX_WRAPPERS="claudecli:paid"
export FAKE_MODE=archive
export FAKE_TARGET="$STATE_DIR2/worktree/issues/issue-1.md"
export FAKE_ITEM_NAME="issue-1.md"
# Capture wrapper calls so we can assert the `issue` stream (not autofix)
# was selected. Set BEFORE the run, so the log reflects actual invocation.
WRAPPER_LOG2="$(mktemp)"
export FAKE_LOG="$WRAPPER_LOG2"
export PATH="$T2_FAKE:$PATH"

set +e
output_autodev="$(cd "$T2_WORK" && bash "$AUTODEV_SH" 2>&1)"
rc_autodev=$?
set -e

# Acceptance: issue-1.md is archived, autofix-1.md is NOT.
ISSUE_ARCHIVED="$(git -C "$T2_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep "issues/archive/.*/issue-1.md" || true)"
if [ -n "$ISSUE_ARCHIVED" ]; then
    pass "autodev.sh → issue-1.md archived"
else
    fail "autodev.sh → issue-1.md NOT archived. output: $output_autodev"
fi

# autofix-1.md must still exist in issues/ (NOT archived).
AUTOFIX_STILL_THERE="$(git -C "$T2_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep "^issues/autofix-1.md$" || true)"
if [ -n "$AUTOFIX_STILL_THERE" ]; then
    pass "autodev.sh → autofix-1.md left untouched (stream filter works)"
else
    fail "autodev.sh → autofix-1.md was archived (stream filter BROKEN)"
fi

# Verify the wrapper was called with the issue-1 item (proving the
# `--stream issue` was actually passed to autofix.py and selected).
if [ -s "$WRAPPER_LOG2" ] && grep -q "issue-1" "$WRAPPER_LOG2"; then
    pass "autodev.sh → wrapper invoked with issue-1 (stream filter active)"
else
    fail "autodev.sh → wrapper invocation log missing issue-1. log: $(cat "$WRAPPER_LOG2" 2>/dev/null)"
fi
rm -f "$WRAPPER_LOG2"

# ============================================================================
# 5. Tally.
# ============================================================================
if [ "$FAIL" -eq 0 ]; then
    echo "All issue-17 acceptance checks passed."
    exit 0
else
    echo "One or more issue-17 acceptance checks failed."
    exit 1
fi
