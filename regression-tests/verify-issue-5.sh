#!/usr/bin/env bash
# Verifies issue-5 acceptance criteria: codexcli/antigravitycli/deepseekcli
# pass-through wrapper ports.
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

declare -A CLI_NAME=(
    [codexcli]=codex
    [antigravitycli]=antigravity
    [deepseekcli]=deepseek
)

# --- criterion: all 9 files exist; .sh executable + bash -n; .ps1/.bat exist ---
for name in "${!CLI_NAME[@]}"; do
    sh="$WRAPPERS/${name}.sh"
    ps1="$WRAPPERS/${name}.ps1"
    bat="$WRAPPERS/${name}.bat"
    cli="${CLI_NAME[$name]}"

    if [ ! -f "$sh" ]; then
        fail "missing $sh"
    else
        [ -x "$sh" ] || fail "$sh is not executable"
        bash -n "$sh" || fail "$sh has a bash syntax error"
    fi

    if [ ! -f "$ps1" ]; then
        fail "missing $ps1"
    else
        grep -q -- "$cli" "$ps1" || fail "$ps1 does not reference '$cli'"
    fi

    if [ ! -f "$bat" ]; then
        fail "missing $bat"
    else
        grep -q -- "$cli" "$bat" || fail "$bat does not reference '$cli'"
    fi
done

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing/invalid wrapper files"
    exit 1
fi

# --- criterion: with fake-claude.sh shadowing each real CLI on PATH,
#     `<name>.sh -p "hi"` records "-p hi" in FAKE_LOG and exits 0 ---
FAKE_BIN_DIR="$TMP_WORK/fakebin"
mkdir -p "$FAKE_BIN_DIR"
for cli in codex antigravity deepseek; do
    ln -sf "$LIB/fake-claude.sh" "$FAKE_BIN_DIR/$cli"
done

for name in "${!CLI_NAME[@]}"; do
    cli="${CLI_NAME[$name]}"
    fake_log="$TMP_WORK/${name}.log"
    rm -f "$fake_log"
    if PATH="$FAKE_BIN_DIR:$PATH" FAKE_LOG="$fake_log" "$WRAPPERS/${name}.sh" -p "hi" > /dev/null; then
        if grep -q -- '-p hi' "$fake_log"; then
            pass "${name}.sh passes through to fake $cli and records '-p hi'"
        else
            fail "${name}.sh did not record '-p hi' in FAKE_LOG"
        fi
    else
        fail "${name}.sh exited non-zero when $cli was on PATH"
    fi
done

# --- criterion: file-arg mode pipes file content to the CLI's stdin ---
prompt_file="$TMP_WORK/prompt.txt"
echo "issue-5 prompt body" > "$prompt_file"
for name in "${!CLI_NAME[@]}"; do
    cli="${CLI_NAME[$name]}"
    stdin_capture="$TMP_WORK/${name}-stdin.txt"
    rm -f "$stdin_capture"
    PATH="$FAKE_BIN_DIR:$PATH" FAKE_STDIN_FILE="$stdin_capture" "$WRAPPERS/${name}.sh" "$prompt_file" > /dev/null
    if [ -f "$stdin_capture" ] && diff -q "$prompt_file" "$stdin_capture" > /dev/null 2>&1; then
        pass "${name}.sh pipes file-argument content to $cli's stdin"
    else
        fail "${name}.sh did not pipe the prompt file's content to $cli's stdin"
    fi
done

# --- criterion: CLI missing from PATH -> exit 127 + [원인]/[조치] ---
EMPTY_PATH_DIR="$TMP_WORK/emptybin"
mkdir -p "$EMPTY_PATH_DIR"
for name in "${!CLI_NAME[@]}"; do
    cli="${CLI_NAME[$name]}"
    stderr_capture="$TMP_WORK/${name}-missing-stderr.txt"
    if PATH="$EMPTY_PATH_DIR:/usr/bin:/bin" "$WRAPPERS/${name}.sh" -p "hi" > /dev/null 2>"$stderr_capture"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -eq 127 ] && grep -q '\[원인\]' "$stderr_capture" && grep -q '\[조치\]' "$stderr_capture"; then
        pass "${name}.sh exits 127 with [원인]/[조치] when $cli is missing from PATH"
    else
        fail "${name}.sh did not exit 127 with [원인]/[조치] when $cli is missing (rc=$rc)"
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-5 acceptance checks passed."
    exit 0
else
    echo "One or more issue-5 acceptance checks failed."
    exit 1
fi
