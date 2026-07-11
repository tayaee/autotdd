#!/usr/bin/env bash
# Verifies issue-29: doctor 결합도·성능 — parse_wrapper_spec core 이동 + usage 중복 실행 제거
# - autoqafix-doctor.py에 import autofix 없음 검증
# - doctor 1회 실행 시 usage 스크립트가 후보별 정확히 1회만 기동하는지 검증
# - select-llm.py 단독 실행 시 동작 불변 (exit 0/2 계약 유지) 검증
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"

FAIL=0
CLEANUP=()

cleanup() {
    for d in "${CLEANUP[@]:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# 1. autoqafix-doctor.py에 import autofix가 없어야 함
if grep -q "import autofix" "$SKILL_DIR/autoqafix-doctor.py"; then
    fail "autoqafix-doctor.py contains 'import autofix'"
else
    pass "No 'import autofix' in autoqafix-doctor.py"
fi

# 2. 픽스처 저장소 생성
fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

# 임시 홈 및 스킬 디렉토리 설정
fake_home="$(mktemp -d)"
CLEANUP+=("$fake_home")
mkdir -p "$fake_home/.claude/skills/autoqafix"
mkdir -p "$fake_home/.claude/skills/autotdd"
mkdir -p "$fake_home/.claude/skills/tdd2"
mkdir -p "$fake_home/.claude/skills/acpd"
mkdir -p "$fake_home/.claude/skills/tdd"

# 복사 대상 파일들을 임시 스킬 경로로 복사
cp "$SKILL_DIR/autoqafix-doctor.py" "$fake_home/.claude/skills/autoqafix/"
cp "$SKILL_DIR/autoqafix_core.py" "$fake_home/.claude/skills/autoqafix/"
cp "$SKILL_DIR/select-llm.py" "$fake_home/.claude/skills/autoqafix/"
cp "$SKILL_DIR/autofix.py" "$fake_home/.claude/skills/autoqafix/"

# deploy.sh 생성
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

# 카운트 파일 경로
COUNT_FILE="$fixture/usage_calls.log"
touch "$COUNT_FILE"

# Fake usage 스크립트 작성
# doctor의 check_usage_scripts 및 select-llm.py 모두에서 실행 가능한 형태
cat > "$fake_home/.claude/skills/autoqafix/usage-fakecli.py" <<EOF
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import os
import sys

# 호출을 파일에 기록
count_file = "$COUNT_FILE"
with open(count_file, "a") as f:
    f.write("call\n")

print(json.dumps({
    "available": True,
    "five_hour_remaining_pct": 80,
    "weekly_remaining_pct": 70,
    "effective_remaining_pct": 75
}))
EOF
chmod +x "$fake_home/.claude/skills/autoqafix/usage-fakecli.py"

# 환경 설정
export AUTOQAFIX_WRAPPERS="fakecli:paid"
export HOME="$fake_home"

# ----- 시나리오 1: doctor 실행 시 후보별 1회 기동 검증 -----
# doctor 실행
python3 "$fake_home/.claude/skills/autoqafix/autoqafix-doctor.py" --repo "$work" > "$fixture/doctor_output.txt" 2>&1
doctor_exit=$?

cat "$fixture/doctor_output.txt"

# 카운트 확인
calls=$(wc -l < "$COUNT_FILE" | tr -d ' ')
if [ "$calls" -eq 1 ]; then
    pass "usage-fakecli.py was called exactly 1 time during doctor run (calls=$calls)"
else
    fail "usage-fakecli.py was called $calls times instead of 1 time"
fi

# ----- 시나리오 2: select-llm.py 단독 실행 시 기존 동작 (exit 0/2 계약 유지) 검증 -----
# 카운트 파일 초기화
> "$COUNT_FILE"

# 단독 실행
selected=$(python3 "$fake_home/.claude/skills/autoqafix/select-llm.py")
llm_exit=$?

if [ "$selected" = "fakecli" ]; then
    pass "select-llm.py selected fakecli"
else
    fail "select-llm.py output was '$selected' instead of 'fakecli'"
fi

if [ "$llm_exit" -eq 0 ]; then
    pass "select-llm.py exited with 0"
else
    fail "select-llm.py exited with $llm_exit instead of 0"
fi

# 단독 실행 시 1회 기동 확인
calls_single=$(wc -l < "$COUNT_FILE" | tr -d ' ')
if [ "$calls_single" -eq 1 ]; then
    pass "usage-fakecli.py was called exactly 1 time during single select-llm.py run"
else
    fail "usage-fakecli.py was called $calls_single times during single run"
fi

# ----- 시나리오 3: 사용량 부족 시 select-llm.py exit 2 계약 검증 -----
# 가용한 사용량이 없는 가짜 스크립트 작성
cat > "$fake_home/.claude/skills/autoqafix/usage-fakecli.py" <<EOF
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
print(json.dumps({
    "available": False,
    "five_hour_remaining_pct": 0,
    "weekly_remaining_pct": 0,
    "effective_remaining_pct": 0
}))
EOF
chmod +x "$fake_home/.claude/skills/autoqafix/usage-fakecli.py"

selected_none=$(python3 "$fake_home/.claude/skills/autoqafix/select-llm.py")
llm_none_exit=$?

if [ "$selected_none" = "none" ]; then
    pass "select-llm.py output is 'none' when not eligible"
else
    fail "select-llm.py output was '$selected_none' instead of 'none'"
fi

if [ "$llm_none_exit" -eq 2 ]; then
    pass "select-llm.py exited with 2 when not eligible"
else
    fail "select-llm.py exited with $llm_none_exit instead of 2"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-29 acceptance checks passed."
    exit 0
else
    echo "One or more issue-29 acceptance checks failed."
    exit 1
fi
