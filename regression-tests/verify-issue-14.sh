#!/usr/bin/env bash
# Verifies issue-14: autoqa tool and its launchers.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
AUTOQA_PY="$SKILL_DIR/autoqa.py"
AUTOQA_SH="$REPO_ROOT/autoqa.sh"
AUTOQA_BAT="$REPO_ROOT/autoqa.bat"
AUTOQA_PS1="$REPO_ROOT/autoqa.ps1"

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

# 1. 파일들 존재 여부 확인 (이 단계에서는 실패해야 정상 - Red)
if [ ! -f "$AUTOQA_PY" ]; then
    fail "missing $AUTOQA_PY"
fi

if [ ! -f "$AUTOQA_SH" ]; then
    fail "missing $AUTOQA_SH"
fi

if [ ! -f "$AUTOQA_BAT" ]; then
    fail "missing $AUTOQA_BAT"
fi

if [ ! -f "$AUTOQA_PS1" ]; then
    fail "missing $AUTOQA_PS1"
fi

# 하나라도 파일이 없으면 즉시 exit
[ "$FAIL" -eq 0 ] || exit 1

# 2. bash -n 통과 검사 및 bat의 pause 검사
if bash -n "$AUTOQA_SH"; then
    pass "bash -n autoqa.sh passed"
else
    fail "bash -n autoqa.sh failed"
fi

if grep -q -i "pause" "$AUTOQA_BAT"; then
    pass "autoqa.bat has 'pause' statement"
else
    fail "autoqa.bat is missing 'pause' statement"
fi

# 3. 픽스처 repo 셋업
fixture_path="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$fixture_path")
work="$fixture_path/work"

# 4. logs/ 없는 디렉토리에서 preflight 실패 검증 (exit 1)
no_logs_work="$(mktemp -d)"
CLEANUP_DIRS+=("$no_logs_work")
# git init 해서 git repo로 만들어 preflight의 logs/ 부분만 유발
git init -q "$no_logs_work"
git -C "$no_logs_work" config user.name "Bot"
git -C "$no_logs_work" config user.email "bot@example.com"
mkdir -p "$no_logs_work/issues"

# 실행
set +e
output_preflight=$(cd "$no_logs_work" && bash "$AUTOQA_SH" 2>&1)
rc_preflight=$?
set -e

if [ "$rc_preflight" -eq 1 ]; then
    pass "Preflight fail test exits 1"
else
    fail "Expected exit 1 on preflight fail, got: $rc_preflight"
fi

if [[ "$output_preflight" == *"[원인]"* ]] && [[ "$output_preflight" == *"[조치]"* ]]; then
    pass "Preflight fail output has [원인] and [조치]"
else
    fail "Expected [원인] and [조치] in output, got: $output_preflight"
fi

# 5. 잠금 파일이 존재할 때 경합 검증 (exit 3)
lock_file="$work/.git/autoqafix.lock"
mkdir -p "$(dirname "$lock_file")"
echo "host=$(hostname)" > "$lock_file"
# 현재 PID를 락 파일에 써서 살아있는 프로세스처럼 모의
echo "pid=$$" >> "$lock_file"
echo "role=qa" >> "$lock_file"
echo "start=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$lock_file"

set +e
output_lock=$(cd "$work" && bash "$AUTOQA_SH" 2>&1)
rc_lock=$?
set -e

if [ "$rc_lock" -eq 3 ]; then
    pass "Lock contention test exits 3"
else
    fail "Expected exit 3 on lock contention, got: $rc_lock"
fi

if [[ "$output_lock" == *"이미 qa이 실행 중"* ]]; then
    pass "Lock contention outputs guidance message"
else
    fail "Expected '이미 qa이 실행 중' in output, got: $output_lock"
fi

# 락 파일 해제
rm -f "$lock_file"

# 6. 정상 픽스처 repo에서 실행 검증 (exit 0)
fake_wrapper_dir="$(mktemp -d)"
CLEANUP_DIRS+=("$fake_wrapper_dir")
cat > "$fake_wrapper_dir/claudecli.sh" << 'EOF'
#!/usr/bin/env bash
echo "가짜 제목"
echo "TIER: local-ok"
EOF
chmod +x "$fake_wrapper_dir/claudecli.sh"

export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
export AUTOQAFIX_WRAPPER="claudecli"
export AUTOQAFIX_WRAPPERS="claudecli:paid"

# log-scan 초기화
uv -q run "$SKILL_DIR/log-scan.py" --repo "$work" > /dev/null

# 에러 1종 추가
log_file="$work/logs/app.main.log"
{
    printf '2026-07-10 12:05:00,000 [ERROR] app.main - Another error\n'
    printf 'Traceback (most recent call last):\n'
    printf '  File "work/src/app.py", line 42, in process\n'
    printf '    result = compute(x)\n'
    printf 'ValueError: verify-issue-14 error\n'
} >> "$log_file"

# 실행
set +e
output_normal=$(cd "$work" && bash "$AUTOQA_SH" 2>&1)
rc_normal=$?
set -e

if [ "$rc_normal" -eq 0 ]; then
    pass "Normal execution exits 0"
else
    fail "Expected exit 0 on normal run, got: $rc_normal. Output: $output_normal"
fi

# autofix-1.md 가 생성되었는지 확인
git -C "$work" pull -q origin main
if [ -f "$work/issues/autofix-1.md" ]; then
    pass "autofix-1.md successfully created under autoqa.sh launcher run"
else
    fail "autofix-1.md not found"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-14 acceptance checks passed."
    exit 0
else
    echo "One or more issue-14 acceptance checks failed."
    exit 1
fi
