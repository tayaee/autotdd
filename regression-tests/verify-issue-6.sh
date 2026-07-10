#!/usr/bin/env bash
# Verifies issue-6 acceptance criteria: qwencli wrapper (local free LLM).
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

# --- criterion: qwencli.sh exists, executable, passes bash -n;
#     .ps1/.bat exist + reference qwen ---
sh="$WRAPPERS/qwencli.sh"
ps1="$WRAPPERS/qwencli.ps1"
bat="$WRAPPERS/qwencli.bat"

if [ ! -f "$sh" ]; then
    fail "missing $sh"
else
    [ -x "$sh" ] || fail "$sh is not executable"
    bash -n "$sh" || fail "$sh has a bash syntax error"
fi

if [ ! -f "$ps1" ]; then
    fail "missing $ps1"
else
    grep -q -- 'qwen' "$ps1" || fail "$ps1 does not reference 'qwen'"
fi

if [ ! -f "$bat" ]; then
    fail "missing $bat"
else
    grep -q -- 'qwen' "$bat" || fail "$bat does not reference 'qwen'"
fi

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing/invalid wrapper files"
    exit 1
fi

# --- criterion: with fake-qwen.sh shadowing `qwen` on PATH,
#     qwencli.sh -p "hi" records "-p hi" in FAKE_LOG and exits 0 ---
FAKE_BIN_DIR="$TMP_WORK/fakebin"
mkdir -p "$FAKE_BIN_DIR"
ln -sf "$LIB/fake-qwen.sh" "$FAKE_BIN_DIR/qwen"

fake_log="$TMP_WORK/qwencli.log"
rm -f "$fake_log"
if PATH="$FAKE_BIN_DIR:$PATH" FAKE_LOG="$fake_log" "$sh" -p "hi" > /dev/null; then
    if grep -q -- '-p hi' "$fake_log"; then
        pass "qwencli.sh passes through to fake qwen and records '-p hi'"
    else
        fail "qwencli.sh did not record '-p hi' in FAKE_LOG"
    fi
else
    fail "qwencli.sh exited non-zero when qwen was on PATH"
fi

# --- requirement 3 (file-arg mode): file path as $1 pipes its content to qwen's stdin ---
prompt_file="$TMP_WORK/prompt.txt"
echo "issue-6 prompt body" > "$prompt_file"
stdin_capture="$TMP_WORK/qwencli-stdin.txt"
rm -f "$stdin_capture"
PATH="$FAKE_BIN_DIR:$PATH" FAKE_STDIN_FILE="$stdin_capture" "$sh" "$prompt_file" > /dev/null
if [ -f "$stdin_capture" ] && diff -q "$prompt_file" "$stdin_capture" > /dev/null 2>&1; then
    pass "qwencli.sh pipes file-argument content to qwen's stdin"
else
    fail "qwencli.sh did not pipe the prompt file's content to qwen's stdin"
fi

# --- criterion: qwen missing from PATH -> exit 127 + [원인]/[조치] ---
EMPTY_PATH_DIR="$TMP_WORK/emptybin"
mkdir -p "$EMPTY_PATH_DIR"
stderr_capture="$TMP_WORK/qwencli-missing-stderr.txt"
if PATH="$EMPTY_PATH_DIR:/usr/bin:/bin" "$sh" -p "hi" > /dev/null 2>"$stderr_capture"; then
    rc=0
else
    rc=$?
fi
if [ "$rc" -eq 127 ] && grep -q '\[원인\]' "$stderr_capture" && grep -q '\[조치\]' "$stderr_capture"; then
    pass "qwencli.sh exits 127 with [원인]/[조치] when qwen is missing from PATH"
else
    fail "qwencli.sh did not exit 127 with [원인]/[조치] when qwen is missing (rc=$rc)"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-6 acceptance checks passed."
    exit 0
else
    echo "One or more issue-6 acceptance checks failed."
    exit 1
fi
