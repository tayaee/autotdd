#!/usr/bin/env bash
# Verifies issue-19: role-loop.py + autoqa-loop/autofix-loop/autodev-loop launchers.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
ROLE_LOOP_PY="$SKILL_DIR/role-loop.py"

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

# 1. 파일 존재: role-loop.py + 런처 9종
if [ ! -f "$ROLE_LOOP_PY" ]; then
    fail "missing $ROLE_LOOP_PY"
fi

for role in qa fix dev; do
    for ext in sh ps1 bat; do
        f="$REPO_ROOT/auto${role}-loop.${ext}"
        if [ ! -f "$f" ]; then
            fail "missing $f"
        fi
    done
done

# 하나라도 없으면 즉시 종료 (Red 단계)
[ "$FAIL" -eq 0 ] || exit 1

# 2. .sh 3종 bash -n, .bat 3종 pause, 롤 매핑 정적 검사
for role in qa fix dev; do
    sh_file="$REPO_ROOT/auto${role}-loop.sh"
    if bash -n "$sh_file"; then
        pass "bash -n auto${role}-loop.sh passed"
    else
        fail "bash -n auto${role}-loop.sh failed"
    fi

    if grep -q -i "pause" "$REPO_ROOT/auto${role}-loop.bat"; then
        pass "auto${role}-loop.bat has 'pause' statement"
    else
        fail "auto${role}-loop.bat is missing 'pause' statement"
    fi

    for ext in sh ps1 bat; do
        f="$REPO_ROOT/auto${role}-loop.${ext}"
        if grep -q -- "--role ${role}" "$f"; then
            pass "auto${role}-loop.${ext} passes --role ${role}"
        else
            fail "auto${role}-loop.${ext} does not pass --role ${role}"
        fi
        if grep -q "role-loop.py" "$f"; then
            pass "auto${role}-loop.${ext} calls role-loop.py"
        else
            fail "auto${role}-loop.${ext} does not call role-loop.py"
        fi
    done
done

# 3. 동작 검사 A: --interval 1, 3초 후 kill → ran 2회 이상
work_a="$(mktemp -d)"
CLEANUP_DIRS+=("$work_a")
out_a="$work_a/out.log"

(
    cd "$work_a"
    AUTOQAFIX_ROLE_CMD="echo ran" setsid bash "$REPO_ROOT/autoqa-loop.sh" --interval 1 > "$out_a" 2>&1 &
    echo $! > "$work_a/pid"
)
sleep 3
kill -TERM -- "-$(cat "$work_a/pid")" 2>/dev/null
wait 2>/dev/null

count_a=$(grep -c '^ran$' "$out_a" || true)
if [ "$count_a" -ge 2 ]; then
    pass "interval=1: 'ran' printed ${count_a} times (>=2) in 3s"
else
    fail "interval=1: expected >=2 'ran', got ${count_a}. Output: $(cat "$out_a")"
fi

# 4. 동작 검사 B: --interval 3600, 3초 내 1회만
work_b="$(mktemp -d)"
CLEANUP_DIRS+=("$work_b")
out_b="$work_b/out.log"

(
    cd "$work_b"
    AUTOQAFIX_ROLE_CMD="echo ran" setsid bash "$REPO_ROOT/autoqa-loop.sh" --interval 3600 > "$out_b" 2>&1 &
    echo $! > "$work_b/pid"
)
sleep 3
kill -TERM -- "-$(cat "$work_b/pid")" 2>/dev/null
wait 2>/dev/null

count_b=$(grep -c '^ran$' "$out_b" || true)
if [ "$count_b" -eq 1 ]; then
    pass "interval=3600: 'ran' printed exactly once in 3s"
else
    fail "interval=3600: expected exactly 1 'ran', got ${count_b}. Output: $(cat "$out_b")"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-19 acceptance checks passed."
    exit 0
else
    echo "One or more issue-19 acceptance checks failed."
    exit 1
fi
