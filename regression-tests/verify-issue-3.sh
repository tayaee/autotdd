#!/usr/bin/env bash
# Verifies issue-3 acceptance criteria: fixture-repo generator + fake tools.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"

FAIL=0
CLEANUP_DIRS=()

cleanup() {
    for d in "${CLEANUP_DIRS[@]:-}"; do
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

# --- criterion 1: bash syntax + executable bits on all lib scripts ---
for script in "$LIB/make-fixture-repo.sh" "$LIB/fake-wrapper.sh" "$LIB/fake-claude.sh" "$LIB/fake-qwen.sh"; do
    if [ ! -f "$script" ]; then
        fail "missing script: $script"
        continue
    fi
    if [ ! -x "$script" ]; then
        fail "not executable: $script"
    fi
    if ! bash -n "$script"; then
        fail "bash syntax error: $script"
    fi
done

if [ "$FAIL" -eq 1 ]; then
    echo "aborting further checks: missing/invalid scripts"
    exit 1
fi

# --- criterion 2: make-fixture-repo.sh run twice yields independent paths ---
path1="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
path2="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$path1" "$path2")

if [ -z "$path1" ] || [ ! -d "$path1" ]; then
    fail "make-fixture-repo.sh did not print a valid path (run 1): '$path1'"
elif [ -z "$path2" ] || [ ! -d "$path2" ]; then
    fail "make-fixture-repo.sh did not print a valid path (run 2): '$path2'"
elif [ "$path1" = "$path2" ]; then
    fail "two runs of make-fixture-repo.sh produced the same path: $path1"
else
    pass "make-fixture-repo.sh produces two independent fixture paths"
fi

# --- criterion 3: work/ has at least one commit ---
if [ -d "$path1/work" ]; then
    commit_count="$(git -C "$path1/work" log --oneline 2>/dev/null | wc -l)"
    if [ "$commit_count" -ge 1 ]; then
        pass "fixture work/ has $commit_count commit(s)"
    else
        fail "fixture work/ has no commits"
    fi
else
    fail "fixture path1 has no work/ directory: $path1"
fi

# --- log file shape check (regression coverage for the fixture generator) ---
log_file="$path1/work/logs/app.main.log"
if [ -f "$log_file" ]; then
    line_count="$(wc -l < "$log_file")"
    tb_count="$(grep -c '^Traceback (most recent call last):$' "$log_file")"
    err_count="$(grep -c '^\S\+ \S\+ \[ERROR\]' "$log_file")"
    warn_count="$(grep -c '^\S\+ \S\+ \[WARNING\]' "$log_file")"
    info_count="$(grep -c '^\S\+ \S\+ \[INFO\]' "$log_file")"
    frame_count="$(grep -c 'work/src/app.py", line 42' "$log_file")"

    [ "$line_count" -ge 30 ] || fail "app.main.log has only $line_count lines (need >= 30)"
    [ "$tb_count" -eq 5 ] || fail "app.main.log has $tb_count traceback blocks (need 5)"
    [ "$frame_count" -eq 5 ] || fail "app.main.log has $frame_count frames at app.py line 42 (need 5)"
    [ "$err_count" -ge 3 ] || fail "app.main.log has $err_count [ERROR] lines (need >= 3 standalone + traceback headers)"
    [ "$warn_count" -eq 2 ] || fail "app.main.log has $warn_count [WARNING] lines (need 2)"
    [ "$info_count" -ge 1 ] || fail "app.main.log has $info_count [INFO] lines (need >= 1)"
    [ "$FAIL" -eq 0 ] && pass "app.main.log matches required shape ($line_count lines)"
else
    fail "missing fixture log file: $log_file"
fi

# --- src/app.py shape check ---
app_py="$path1/work/src/app.py"
if [ -f "$app_py" ]; then
    py_lines="$(wc -l < "$app_py")"
    [ "$py_lines" -ge 50 ] && [ "$(sed -n '42p' "$app_py")" != "" ] \
        && pass "app.py has $py_lines lines with a non-empty line 42" \
        || fail "app.py does not satisfy 50+ lines / non-empty line 42"
else
    fail "missing fixture file: $app_py"
fi

# --- criterion 4: FAKE_MODE=archive moves file to issues/archive/YYYY/MM/DD and pushes ---
archive_target="issues/autofix-1.md"
(
    cd "$path1/work" || exit 1
    mkdir -p issues
    echo "# autofix-1: test" > "$archive_target"
    git add "$archive_target"
    git commit -q -m "seed autofix-1 for archive test"
)
(cd "$path1/work" && FAKE_MODE=archive FAKE_TARGET="$archive_target" "$LIB/fake-wrapper.sh" -p x > /dev/null)
expected_archive_path="$path1/work/issues/archive/$(date +%Y/%m/%d)/autofix-1.md"
if [ -f "$expected_archive_path" ]; then
    pushed_log="$(git -C "$path1/work" log --oneline origin/main 2>/dev/null | head -n 1)"
    if git -C "$path1/work" show "origin/main:issues/archive/$(date +%Y/%m/%d)/autofix-1.md" > /dev/null 2>&1; then
        pass "fake-wrapper.sh FAKE_MODE=archive moved and pushed the file"
    else
        fail "archived file exists locally but was not pushed to origin"
    fi
else
    fail "fake-wrapper.sh FAKE_MODE=archive did not create $expected_archive_path"
fi

# --- criterion 5: FAKE_MODE=fail exits 1, FAKE_MODE=ok exits 0 ---
if FAKE_MODE=fail "$LIB/fake-wrapper.sh" -p x > /dev/null 2>/tmp/fake-wrapper-fail-stderr.$$; then
    fail "FAKE_MODE=fail did not exit non-zero"
else
    if [ -s "/tmp/fake-wrapper-fail-stderr.$$" ]; then
        pass "FAKE_MODE=fail exits 1 with a stderr message"
    else
        fail "FAKE_MODE=fail exited 1 but printed nothing to stderr"
    fi
fi
rm -f "/tmp/fake-wrapper-fail-stderr.$$"

if FAKE_MODE=ok "$LIB/fake-wrapper.sh" -p x > /dev/null 2>&1; then
    pass "FAKE_MODE=ok exits 0"
else
    fail "FAKE_MODE=ok did not exit 0"
fi

# --- FAKE_LOG append check ---
fake_log="$path1/fake.log"
rm -f "$fake_log"
FAKE_MODE=ok FAKE_LOG="$fake_log" "$LIB/fake-wrapper.sh" -p "hello world" > /dev/null
if [ -f "$fake_log" ] && grep -q -- "-p hello world" "$fake_log"; then
    pass "fake-wrapper.sh appends invocation args to FAKE_LOG"
else
    fail "fake-wrapper.sh did not append expected args to FAKE_LOG"
fi

# --- fake-claude.sh / fake-qwen.sh basic behavior ---
for tool in fake-claude.sh fake-qwen.sh; do
    tool_log="$path1/${tool}.log"
    rm -f "$tool_log"
    out="$(FAKE_LOG="$tool_log" "$LIB/$tool" -p "hi" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "pong" ] && grep -q -- "-p hi" "$tool_log"; then
        pass "$tool logs args and prints pong"
    else
        fail "$tool did not behave as expected (rc=$rc out='$out')"
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-3 acceptance checks passed."
    exit 0
else
    echo "One or more issue-3 acceptance checks failed."
    exit 1
fi
