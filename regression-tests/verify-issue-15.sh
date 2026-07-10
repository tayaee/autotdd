#!/usr/bin/env bash
# Verifies issue-15: autofix/autodev engine skeleton (worktree + per-item
# tier handling + dispatch stub).
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

# -- fixture -----------------------------------------------------------------
fixture_tmp="$(bash "$LIB/make-fixture-repo-issue-15.sh" | tail -n 1)"
CLEANUP+=("$fixture_tmp")
work="$fixture_tmp/work"

# Pre-conditions for the human main tree.
if [ "$(cat "$work/UNTRACKED_DUMMY")" != "human-main-tree-untouched" ]; then
    fail "fixture setup: UNTRACKED_DUMMY missing or altered pre-run"
fi

# Drop any cached state from previous runs against the same fixture path.
clone_id="$(python3 -c 'import sys,hashlib;print(hashlib.sha1(sys.argv[1].encode()).hexdigest()[:12])' "$work")"
state_dir="$HOME/.cache/autoqafix/$clone_id"
rm -rf "$state_dir"

# -- fake wrapper ------------------------------------------------------------
fake_wrapper_dir="$(mktemp -d)"
CLEANUP+=("$fake_wrapper_dir")

# Content-aware tier judgement: marker in the prompt chooses the tier.
# Markers live in the fixture item files (see make-fixture-repo-issue-15.sh).
cat > "$fake_wrapper_dir/claudecli.sh" <<'EOF'
#!/usr/bin/env bash
prompt="$*"
if [[ "$prompt" == *"EXPECT-TIER-MANUAL"* ]]; then
    echo "fixture body ignored"
    echo "TIER: manual"
elif [[ "$prompt" == *"EXPECT-TIER-LOCAL-OK"* ]]; then
    echo "fixture body ignored"
    echo "TIER: local-ok"
else
    echo "fixture body ignored"
    echo "TIER: local-ok"
fi
exit 0
EOF
chmod +x "$fake_wrapper_dir/claudecli.sh"

# qwencli is local-tier; in scenario B nothing should reach this script for
# tier judgement, but keep one anyway so the wrapper dir is consistent.
cat > "$fake_wrapper_dir/qwencli.sh" <<'EOF'
#!/usr/bin/env bash
echo "fixture qwencli"
echo "TIER: local-ok"
EOF
chmod +x "$fake_wrapper_dir/qwencli.sh"

# -- Scenario A: paid (claudecli) — manual rename + local-ok dispatch ---------
export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
export AUTOQAFIX_WRAPPERS="claudecli:paid,qwencli:local"
export AUTOQAFIX_WRAPPER="claudecli"

set +e
output_A="$(uv -q run "$AUTOFIX_PY" --repo "$work" --stream autofix 2>&1)"
rc_A=$?
set -e

if [ "$rc_A" -eq 0 ]; then
    pass "Scenario A: exit 0"
else
    fail "Scenario A: expected exit 0, got $rc_A — output: $output_A"
fi

# Suffix / reservation items never reach dispatch.
if [[ "$output_A" == *"DISPATCH autofix-4-later"* ]]; then
    fail "Scenario A: -later surfaced"
else
    pass "Scenario A: -later filtered"
fi
if [[ "$output_A" == *"DISPATCH autofix-5-manual"* ]]; then
    fail "Scenario A: -manual surfaced"
else
    pass "Scenario A: -manual filtered"
fi
if [[ "$output_A" == *"DISPATCH autofix-6-agent-failed"* ]]; then
    fail "Scenario A: -agent-failed surfaced"
else
    pass "Scenario A: -agent-failed filtered"
fi
if [[ "$output_A" == *"DISPATCH autofix-7"* ]]; then
    fail "Scenario A: reservation-only (no '## ') surfaced"
else
    pass "Scenario A: reservation-only filtered"
fi

# autofix-1 (judged manual) → -manual rename + no DISPATCH.
git -C "$work" pull -q origin main
if [ -f "$work/issues/autofix-1-manual.md" ] && [ ! -f "$work/issues/autofix-1.md" ]; then
    pass "Scenario A: autofix-1 → -manual rename"
else
    fail "Scenario A: autofix-1 -manual rename not detected (work listing: $(ls "$work/issues" | tr '\n' ' '))"
fi
if [[ "$output_A" == *"DISPATCH autofix-1"* ]]; then
    fail "Scenario A: DISPATCH line emitted for manual-stamped item"
else
    pass "Scenario A: no DISPATCH for manual-renamed item"
fi
# -manual file carries the stamp that triggered the rename.
if grep -q "^agent-tier: manual$" "$work/issues/autofix-1-manual.md"; then
    pass "Scenario A: -manual file carries agent-tier: manual stamp"
else
    fail "Scenario A: -manual file missing agent-tier: manual stamp"
fi

# autofix-2 (judged local-ok) → stamp + DISPATCH.
if [ -f "$work/issues/autofix-2.md" ] && grep -q "^agent-tier: local-ok$" "$work/issues/autofix-2.md"; then
    pass "Scenario A: autofix-2 stamped agent-tier: local-ok"
else
    fail "Scenario A: autofix-2 stamp missing"
fi
if [[ "$output_A" == *"DISPATCH autofix-2 claudecli"* ]]; then
    pass "Scenario A: DISPATCH autofix-2 claudecli"
else
    fail "Scenario A: missing DISPATCH autofix-2 claudecli"
fi

# autofix-3 (paid-only stamp, paid selection) → matches → DISPATCH.
if [[ "$output_A" == *"DISPATCH autofix-3 claudecli"* ]]; then
    pass "Scenario A: DISPATCH autofix-3 claudecli (paid-only stamp matches paid selection)"
else
    fail "Scenario A: missing DISPATCH autofix-3 claudecli"
fi

# Last stdout line must be FIXED=0.
last_line="$(echo "$output_A" | tail -n 1)"
if [ "$last_line" = "FIXED=0" ]; then
    pass "Scenario A: last line FIXED=0"
else
    fail "Scenario A: last line is not FIXED=0 (got: $last_line)"
fi

# Human main tree untouched (work/'s UNTRACKED_DUMMY survives scenario A).
if [ "$(cat "$work/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
    pass "Scenario A: human main tree untracked dummy untouched"
else
    fail "Scenario A: human main tree UNTRACKED_DUMMY altered"
fi

# Worktree was actually created under state_dir. `.git` is a gitfile
# (a file containing `gitdir: ...`), not a directory, in a linked worktree.
if [ -d "$state_dir/worktree" ] && [ -e "$state_dir/worktree/.git" ]; then
    pass "Scenario A: agent worktree created under state_dir"
else
    fail "Scenario A: state_dir/worktree not created"
fi

# -- Scenario B: local (qwencli) — paid-only stamp must skip -----------------
export AUTOQAFIX_WRAPPER="qwencli"

# Sync the human tree before scenario B (autofix.py itself only touches the
# worktree, not work/).
git -C "$work" pull -q origin main

set +e
output_B="$(uv -q run "$AUTOFIX_PY" --repo "$work" --stream autofix 2>&1)"
rc_B=$?
set -e

if [ "$rc_B" -eq 0 ]; then
    pass "Scenario B: exit 0"
else
    fail "Scenario B: expected exit 0, got $rc_B — output: $output_B"
fi

# autofix-3 (paid-only stamp) + local selection → SKIP. File must NOT change.
before_hash="$(git -C "$work" ls-tree origin/main issues/autofix-3.md | awk '{print $3}')"
git -C "$work" pull -q origin main
after_hash="$(git -C "$work" ls-tree HEAD issues/autofix-3.md | awk '{print $3}')"
if [ "$before_hash" = "$after_hash" ]; then
    pass "Scenario B: autofix-3 file unchanged when local meets paid-only"
else
    fail "Scenario B: autofix-3 changed under local selection (before=$before_hash after=$after_hash)"
fi
if [[ "$output_B" == *"DISPATCH autofix-3"* ]]; then
    fail "Scenario B: DISPATCH autofix-3 emitted under local selection"
else
    pass "Scenario B: autofix-3 not dispatched under local selection"
fi

# autofix-2 (local-ok stamp) + local selection → MATCH → DISPATCH.
if [[ "$output_B" == *"DISPATCH autofix-2 qwencli"* ]]; then
    pass "Scenario B: DISPATCH autofix-2 qwencli (local-ok stamp matches local)"
else
    fail "Scenario B: missing DISPATCH autofix-2 qwencli"
fi

# Last stdout line still FIXED=0 (issue-15 stub).
last_line_B="$(echo "$output_B" | tail -n 1)"
if [ "$last_line_B" = "FIXED=0" ]; then
    pass "Scenario B: last line FIXED=0"
else
    fail "Scenario B: last line is not FIXED=0 (got: $last_line_B)"
fi

# Human main tree still untouched after scenario B too.
if [ "$(cat "$work/UNTRACKED_DUMMY")" = "human-main-tree-untouched" ]; then
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