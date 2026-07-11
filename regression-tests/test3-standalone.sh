#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="/home/user1/git/autotdd"
AUTOFIX_PY="$REPO_ROOT/.claude/skills/autoqafix/autofix.py"

T3_FIXTURE="$(mktemp -d)"
T3_ORIGIN="$T3_FIXTURE/origin"
T3_WORK="$T3_FIXTURE/work"
T3_FAKE="$T3_FIXTURE/fake"
mkdir -p "$T3_WORK" "$T3_FAKE"

git init -q --bare "$T3_ORIGIN"
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

CID3="$(echo -n "$T3_WORK" | sha1sum | cut -c1-12)"
STATE_DIR3="$HOME/.cache/autoqafix/$CID3"
mkdir -p "$STATE_DIR3"

# Clean up stale state.
rm -rf "$STATE_DIR3/worktree" 2>/dev/null

echo "=== Before run ==="
echo "STATE_DIR3=$STATE_DIR3"
echo "WT_EXISTS=$(test -d "$STATE_DIR3/worktree" && echo yes || echo no)"
echo "FAKE_MODE=hang"
echo "AUTOQAFIX_IMPL_TIMEOUT=3"

# Run with timeout.
timeout 15 bash -c '
FAKE_MODE=hang FAKE_ITEM_NAME="autofix-1.md" \
    AUTOQAFIX_WRAPPER_DIR="$T3_FAKE" AUTOQAFIX_WRAPPER="claudecli" PATH="$T3_FAKE:$PATH" \
    AUTOQAFIX_IMPL_TIMEOUT=3 \
    python3 "'"$AUTOFIX_PY"'" --repo "'"$T3_WORK"'" --stream autofix 2>&1
echo "RESULT: $?"
' 2>&1

echo "=== After run ==="
echo "WT_EXISTS=$(test -d "$STATE_DIR3/worktree" && echo yes || echo no)"
echo "WT_ITEMS=$(ls "$STATE_DIR3/worktree/issues/" 2>/dev/null || echo '(empty)')"
AF="$(git -C "$T3_ORIGIN" ls-tree -r main --name-only 2>/dev/null | grep '\-agent-failed\.md$' | head -n1)"
echo "AGENT_FAILED=$AF"
if [ -n "$AF" ]; then
    git -C "$T3_ORIGIN" cat-file -p "$(git -C "$T3_ORIGIN" rev-parse "main:$AF")" 2>&1 | grep -c "timeout"
fi

rm -rf "$T3_FIXTURE" "$STATE_DIR3"
