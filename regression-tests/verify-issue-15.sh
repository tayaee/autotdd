#!/usr/bin/env bash
# Verifies issue-15: autofix/autodev engine skeleton (worktree + per-item
# tier handling). Originally written against issue-15's dispatch *stub*
# (`DISPATCH ...` stdout lines, fixed FIXED=0); issue-16 replaced the stub
# with real dispatch (success = archive presence), so this script now
# verifies the same skeleton behaviors through real dispatch outcomes.
# See verify-issue-15.conflict-with-16.md.
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

# -- file existence (Red gate) ------------------------------------------------
if [ ! -f "$AUTOFIX_PY" ]; then
    fail "missing $AUTOFIX_PY"
    exit 1
fi
pass "autofix.py exists"

# -- fake wrapper dir ---------------------------------------------------------
# Tier judgement calls carry the item content (EXPECT-TIER-* markers);
# dispatch calls carry "/autotdd <stem> worktree" and are delegated to
# lib/fake-wrapper.sh's archive mode (success = item reaches archive/).
fake_wrapper_dir="$(mktemp -d)"
CLEANUP+=("$fake_wrapper_dir")

make_fake() {
    local name="$1"
    cat > "$fake_wrapper_dir/$name.sh" <<EOF
#!/usr/bin/env bash
prompt="\$*"
case "\$prompt" in
    *"/autotdd "*)
        FAKE_MODE=archive exec bash "$LIB/fake-wrapper.sh" "\$@"
        ;;
esac
if [[ "\$prompt" == *"EXPECT-TIER-MANUAL"* ]]; then
    echo "fixture body ignored"
    echo "TIER: manual"
else
    echo "fixture body ignored"
    echo "TIER: local-ok"
fi
exit 0
EOF
    chmod +x "$fake_wrapper_dir/$name.sh"
}
make_fake claudecli
make_fake qwencli

state_dir_of() {
    local cid
    cid="$(python3 -c 'import sys,hashlib;print(hashlib.sha1(sys.argv[1].encode()).hexdigest()[:12])' "$1")"
    echo "$HOME/.cache/autoqafix/$cid"
}

export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
export AUTOQAFIX_WRAPPERS="claudecli:paid,qwencli:local"

# =============================================================================
# Scenario A: paid (claudecli) — filter, manual rename, stamp, dispatch
# =============================================================================
fixture_A="$(bash "$LIB/make-fixture-repo-issue-15.sh" | tail -n 1)"
CLEANUP+=("$fixture_A")
work_A="$fixture_A/work"

if [ "$(cat "$work_A/UNTRACKED_DUMMY")" != "human-main-tree-untouched" ]; then
    fail "fixture setup: UNTRACKED_DUMMY missing or altered pre-run"
fi

state_A="$(state_dir_of "$work_A")"
rm -rf "$state_A"
CLEANUP+=("$state_A")

export AUTOQAFIX_WRAPPER="claudecli"

set +e
output_A="$(uv -q run "$AUTOFIX_PY" --repo "$work_A" --stream autofix 2>&1)"
rc_A=$?
set -e

if [ "$rc_A" -eq 0 ]; then
    pass "Scenario A: exit 0"
else
    fail "Scenario A: expected exit 0, got $rc_A — output: $output_A"
fi

git -C "$work_A" pull -q origin main

# Suffix / reservation items are filtered before any tier logic: they stay
# in issues/ untouched (not archived, not renamed).
for f in autofix-4__STATE-later autofix-5__STATE-manual autofix-6__STATE-agent-failed autofix-7; do
    if [ -f "$work_A/issues/$f.md" ]; then
        pass "Scenario A: $f untouched (filtered)"
    else
        fail "Scenario A: $f missing from issues/ — filter failed"
    fi
done

# autofix-1 (judged manual) → __STATE-manual rename, never dispatched/archived.
if [ -f "$work_A/issues/autofix-1__STATE-manual.md" ] && [ ! -f "$work_A/issues/autofix-1.md" ]; then
    pass "Scenario A: autofix-1 → __STATE-manual rename"
else
    fail "Scenario A: autofix-1 __STATE-manual rename not detected (work listing: $(ls "$work_A/issues" | tr '\n' ' '))"
fi
if grep -q "^agent-tier: manual$" "$work_A/issues/autofix-1__STATE-manual.md" 2>/dev/null; then
    pass "Scenario A: __STATE-manual file carries agent-tier: manual stamp"
else
    fail "Scenario A: __STATE-manual file missing agent-tier: manual stamp"
fi
if find "$work_A/issues/archive" -name "autofix-1*.md" 2>/dev/null | grep -q .; then
    fail "Scenario A: manual item was dispatched (found in archive/)"
else
    pass "Scenario A: manual item not dispatched"
fi

# autofix-2 (judged local-ok) → stamped, then dispatched → archived.
ARCHIVED_2="$(find "$work_A/issues/archive" -name "autofix-2.md" 2>/dev/null | head -n1)"
if [ -n "$ARCHIVED_2" ]; then
    pass "Scenario A: autofix-2 dispatched → archived"
else
    fail "Scenario A: autofix-2 not archived"
fi
if [ -n "$ARCHIVED_2" ] && grep -q "^agent-tier: local-ok$" "$ARCHIVED_2"; then
    pass "Scenario A: autofix-2 carries agent-tier: local-ok stamp"
else
    fail "Scenario A: autofix-2 stamp missing"
fi

# autofix-3 (paid-only stamp, paid selection) → matches → dispatched.
if find "$work_A/issues/archive" -name "autofix-3.md" 2>/dev/null | grep -q .; then
    pass "Scenario A: autofix-3 dispatched → archived (paid-only matches paid)"
else
    fail "Scenario A: autofix-3 not archived under paid selection"
fi

# Last stdout line: two successful dispatches.
last_line="$(echo "$output_A" | tail -n 1)"
if [ "$last_line" = "FIXED=2" ]; then
    pass "Scenario A: last line FIXED=2"
else
    fail "Scenario A: last line is not FIXED=2 (got: $last_line)"
fi

if [ "$(cat "$work_A/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
    pass "Scenario A: human main tree untracked dummy untouched"
else
    fail "Scenario A: human main tree UNTRACKED_DUMMY altered"
fi

# Worktree was actually created under state_dir. `.git` is a gitfile
# (a file containing `gitdir: ...`), not a directory, in a linked worktree.
if [ -d "$state_A/worktree" ] && [ -e "$state_A/worktree/.git" ]; then
    pass "Scenario A: agent worktree created under state_dir"
else
    fail "Scenario A: state_dir/worktree not created"
fi

# =============================================================================
# Scenario B: local (qwencli) — paid-only skip, unstamped skip,
# pre-stamped local-ok dispatch. Fresh fixture (scenario A archived its
# dispatchable items).
# =============================================================================
fixture_B="$(bash "$LIB/make-fixture-repo-issue-15.sh" | tail -n 1)"
CLEANUP+=("$fixture_B")
work_B="$fixture_B/work"

# Pre-stamp autofix-2 as local-ok so a local selection may dispatch it.
sed -i '1a agent-tier: local-ok' "$work_B/issues/autofix-2.md"
git -C "$work_B" add issues/autofix-2.md
git -C "$work_B" commit -q -m "pre-stamp autofix-2 local-ok"
git -C "$work_B" push -q origin main

state_B="$(state_dir_of "$work_B")"
rm -rf "$state_B"
CLEANUP+=("$state_B")

export AUTOQAFIX_WRAPPER="qwencli"

set +e
output_B="$(uv -q run "$AUTOFIX_PY" --repo "$work_B" --stream autofix 2>&1)"
rc_B=$?
set -e

if [ "$rc_B" -eq 0 ]; then
    pass "Scenario B: exit 0"
else
    fail "Scenario B: expected exit 0, got $rc_B — output: $output_B"
fi

before_hash="$(git -C "$work_B" ls-tree origin/main issues/autofix-3.md | awk '{print $3}')"
git -C "$work_B" pull -q origin main
after_hash="$(git -C "$work_B" ls-tree HEAD issues/autofix-3.md | awk '{print $3}')"

# autofix-3 (paid-only stamp) + local selection → SKIP: unchanged, not archived.
if [ -n "$before_hash" ] && [ "$before_hash" = "$after_hash" ]; then
    pass "Scenario B: autofix-3 file unchanged when local meets paid-only"
else
    fail "Scenario B: autofix-3 changed under local selection (before=$before_hash after=$after_hash)"
fi
if find "$work_B/issues/archive" -name "autofix-3.md" 2>/dev/null | grep -q .; then
    fail "Scenario B: autofix-3 dispatched under local selection"
else
    pass "Scenario B: autofix-3 not dispatched under local selection"
fi

# autofix-1 (unstamped) + local selection → SKIP (local can't judge tier).
if [ -f "$work_B/issues/autofix-1.md" ] && ! grep -q "^agent-tier:" "$work_B/issues/autofix-1.md"; then
    pass "Scenario B: unstamped autofix-1 skipped (no stamp, no rename)"
else
    fail "Scenario B: unstamped autofix-1 was touched under local selection"
fi

# autofix-2 (pre-stamped local-ok) + local selection → dispatched → archived.
if find "$work_B/issues/archive" -name "autofix-2.md" 2>/dev/null | grep -q .; then
    pass "Scenario B: autofix-2 dispatched under local selection (local-ok match)"
else
    fail "Scenario B: autofix-2 not archived under local selection"
fi

last_line_B="$(echo "$output_B" | tail -n 1)"
if [ "$last_line_B" = "FIXED=1" ]; then
    pass "Scenario B: last line FIXED=1"
else
    fail "Scenario B: last line is not FIXED=1 (got: $last_line_B)"
fi

if [ "$(cat "$work_B/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
    pass "Scenario B: human main tree untracked dummy untouched"
else
    fail "Scenario B: human main tree UNTRACKED_DUMMY altered"
fi

# -- summary ------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "All issue-15 acceptance checks passed."
    exit 0
else
    echo "One or more issue-15 acceptance checks failed."
    exit 1
fi
