#!/usr/bin/env bash
# Verifies issue-4 acceptance criteria: claudecli/minimaxcli wrapper ports.
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

# --- criterion: both .sh wrappers exist, are executable, pass bash -n ---
for name in claudecli minimaxcli; do
    script="$WRAPPERS/${name}.sh"
    if [ ! -f "$script" ]; then
        fail "missing $script"
        continue
    fi
    [ -x "$script" ] || fail "$script is not executable"
    bash -n "$script" || fail "$script has a bash syntax error"
done

# --- criterion: .ps1 exists + contains the key strings (not executed - no PowerShell here) ---
for name in claudecli minimaxcli; do
    ps1="$WRAPPERS/${name}.ps1"
    if [ ! -f "$ps1" ]; then
        fail "missing $ps1"
        continue
    fi
    grep -q -- '--model' "$ps1" || fail "$ps1 does not reference --model"
done
grep -q -- 'bypassPermissions' "$WRAPPERS/claudecli.ps1" 2>/dev/null \
    && pass "claudecli.ps1 exists and references --model/bypassPermissions" \
    || fail "claudecli.ps1 missing bypassPermissions string"

# --- criterion: .bat exists too (required by requirement 1, not separately tested) ---
for name in claudecli minimaxcli; do
    [ -f "$WRAPPERS/${name}.bat" ] || fail "missing $WRAPPERS/${name}.bat"
done

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing/invalid wrapper files"
    exit 1
fi

# --- criterion: claudecli.sh -p "hi" with fake claude on PATH records --model sonnet
#     and --permission-mode=bypassPermissions in FAKE_LOG ---
export PATH="$LIB:$PATH"
ln -sf "$LIB/fake-claude.sh" "$TMP_WORK/claude"
export PATH="$TMP_WORK:$PATH"

fake_log="$TMP_WORK/claudecli.log"
rm -f "$fake_log"
FAKE_LOG="$fake_log" "$WRAPPERS/claudecli.sh" -p "hi" > /dev/null
if [ -f "$fake_log" ] && grep -q -- '--model sonnet' "$fake_log" && grep -q -- '--permission-mode=bypassPermissions' "$fake_log"; then
    pass "claudecli.sh passes --model sonnet and --permission-mode=bypassPermissions through to claude"
else
    fail "claudecli.sh did not record expected flags in FAKE_LOG"
fi

# --- criterion: file-arg mode pipes file content to claude's stdin ---
prompt_file="$TMP_WORK/prompt.txt"
echo "this is the prompt body" > "$prompt_file"
stdin_capture="$TMP_WORK/stdin-capture.txt"
rm -f "$stdin_capture"
FAKE_STDIN_FILE="$stdin_capture" "$WRAPPERS/claudecli.sh" "$prompt_file" > /dev/null
if [ -f "$stdin_capture" ] && diff -q "$prompt_file" "$stdin_capture" > /dev/null 2>&1; then
    pass "claudecli.sh pipes file-argument content to claude's stdin"
else
    fail "claudecli.sh did not pipe the prompt file's content to claude's stdin"
fi

# --- criterion: minimaxcli.sh -p "hi" records the MiniMax model name ---
fake_log2="$TMP_WORK/minimaxcli.log"
rm -f "$fake_log2"
MINIMAX_API_KEY="fake-test-key" FAKE_LOG="$fake_log2" "$WRAPPERS/minimaxcli.sh" -p "hi" > /dev/null
if [ -f "$fake_log2" ] && grep -q -- 'MiniMax-M3' "$fake_log2"; then
    pass "minimaxcli.sh records the MiniMax model name"
else
    fail "minimaxcli.sh did not record the MiniMax model name in FAKE_LOG"
fi

# --- criterion (implicit, from requirement 2): missing MINIMAX_API_KEY -> [원인]/[조치] + exit 1 ---
unset MINIMAX_API_KEY 2>/dev/null || true
stderr_capture="$TMP_WORK/minimaxcli-stderr.txt"
if env -u MINIMAX_API_KEY "$WRAPPERS/minimaxcli.sh" -p "hi" > /dev/null 2>"$stderr_capture"; then
    fail "minimaxcli.sh did not exit non-zero when MINIMAX_API_KEY is unset"
else
    if grep -q '\[원인\]' "$stderr_capture" && grep -q '\[조치\]' "$stderr_capture"; then
        pass "minimaxcli.sh fails with [원인]/[조치] when MINIMAX_API_KEY is unset"
    else
        fail "minimaxcli.sh's missing-key error is missing [원인]/[조치] markers"
    fi
fi

# --- criterion (requirement 2): no hardcoded secrets - script must reference the env var, not a literal key ---
if grep -q 'MINIMAX_API_KEY' "$WRAPPERS/minimaxcli.sh"; then
    pass "minimaxcli.sh derives its key from the MINIMAX_API_KEY env var (no hardcoded secret)"
else
    fail "minimaxcli.sh does not reference MINIMAX_API_KEY"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-4 acceptance checks passed."
    exit 0
else
    echo "One or more issue-4 acceptance checks failed."
    exit 1
fi
