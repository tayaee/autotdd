#!/usr/bin/env bash
# Verifies issue-13: error-to-autofix pipeline implementation.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
ERROR_TO_AUTOFIX="$SKILL_DIR/error-to-autofix.py"

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

# 1. 파일 존재 여부 확인
if [ ! -f "$ERROR_TO_AUTOFIX" ]; then
    fail "missing $ERROR_TO_AUTOFIX"
    exit 1
fi

# 2. 임시 픽스처 저장소 및 래퍼 설정
fixture_path="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$fixture_path")
work="$fixture_path/work"
origin="$fixture_path/origin.git"

# 가짜 래퍼 준비 디렉토리
fake_wrapper_dir="$(mktemp -d)"
CLEANUP_DIRS+=("$fake_wrapper_dir")

cat > "$fake_wrapper_dir/claudecli.sh" << 'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_OUTPUT_FILE:-}" ] && [ -f "$FAKE_OUTPUT_FILE" ]; then
    cat "$FAKE_OUTPUT_FILE"
else
    echo "가짜 래퍼 제목"
    echo "## 배경"
    echo "에러 수정 배경 설명"
    echo "## 요구사항"
    echo "에러 수정 요구사항"
    echo "## 승인 기준"
    echo "에러 수정 승인 기준"
    echo "TIER: local-ok"
fi
EOF
chmod +x "$fake_wrapper_dir/claudecli.sh"

# 환경변수 세팅
export AUTOQAFIX_WRAPPER_DIR="$fake_wrapper_dir"
export AUTOQAFIX_WRAPPER="claudecli"

# 1차 스캔으로 offsets.json 초기화
uv -q run "$SKILL_DIR/log-scan.py" --repo "$work" > /dev/null

# 3. 에러 1개 추가 (보고 대상)
log_file="$work/logs/app.main.log"
{
    printf '2026-07-10 12:05:00,000 [ERROR] app.main - Another error\n'
    printf 'Traceback (most recent call last):\n'
    printf '  File "work/src/app.py", line 42, in process\n'
    printf '    result = compute(x)\n'
    printf 'ValueError: first test error\n'
} >> "$log_file"

# 실행 1: AUTOQAFIX_WRAPPER=claudecli -> autofix-1.md 생성 검증
# 가짜 래퍼 응답 설정
fake_response="$(mktemp)"
CLEANUP_DIRS+=("$fake_response")
cat > "$fake_response" << 'EOF'
# autofix-1: 로그 에러 ValueError 해결
## 배경
ValueError 처리 로직 추가 필요.
## 요구사항
- ValueError 시 예외 복구
## 승인 기준
- 에러 복구 후 정상 반환
TIER: local-ok
EOF
export FAKE_OUTPUT_FILE="$fake_response"

# 실행
uv -q run "$ERROR_TO_AUTOFIX" --repo "$work"

# 원격 저장소에 올라갔는지 확인하기 위해 origin.git에서 clone해서 확인하거나,
# work 디렉토리에서 git pull 또는 git log 확인
git -C "$work" pull -q origin main

autofix_file="$work/issues/autofix-1.md"
if [ -f "$autofix_file" ]; then
    pass "autofix-1.md successfully created"
    
    # 5대 요소 검증
    # 1. dedup-key
    # 2. agent-tier
    # 3. frequency
    # 4. 발췌 (```log ... ```)
    # 5. 지시문
    content=$(cat "$autofix_file")
    if [[ "$content" == *"dedup-key:"* ]] && \
       [[ "$content" == *"agent-tier:"* ]] && \
       [[ "$content" == *"frequency:"* ]] && \
       [[ "$content" == *"로그 원문(logs/)을 열지 말 것"* ]] && \
       [[ "$content" == *"ValueError: first test error"* ]]; then
        pass "autofix-1.md contains all 5 required elements"
    else
        fail "autofix-1.md is missing some required elements"
    fi
else
    fail "autofix-1.md was not created"
fi

# 4. 즉시 재실행 시 중복 제거 검증
# 추가 파일이나 새로운 커밋이 생기지 않아야 함.
before_commit=$(git -C "$work" rev-parse HEAD)
uv -q run "$ERROR_TO_AUTOFIX" --repo "$work"
git -C "$work" pull -q origin main
after_commit=$(git -C "$work" rev-parse HEAD)

if [ "$before_commit" = "$after_commit" ]; then
    pass "Re-running immediately does not create new issues (dedup check passed)"
else
    fail "Re-running immediately created new commits"
fi

# 5. TIER: manual 응답 검증 -> autofix-2-manual.md 로 변경되어 올라가야 함
# 새 에러 추가
{
    printf '2026-07-10 12:06:00,000 [ERROR] app.main - Manual error\n'
    printf 'Traceback (most recent call last):\n'
    printf '  File "work/src/app.py", line 42, in process\n'
    printf '    result = compute(x)\n'
    printf 'TypeError: manual test error\n'
} >> "$log_file"

# 가짜 래퍼 응답 설정
cat > "$fake_response" << 'EOF'
# autofix-2: 로그 에러 ValueError 수동 해결
## 배경
수동 개입이 필요한 에러.
TIER: manual
EOF

uv -q run "$ERROR_TO_AUTOFIX" --repo "$work"
git -C "$work" pull -q origin main

manual_file="$work/issues/autofix-2-manual.md"
if [ -f "$manual_file" ]; then
    pass "autofix-2-manual.md successfully created and staged/committed as manual"
else
    fail "autofix-2-manual.md was not found"
fi

# 6. select-llm이 none 인 유료 LLM 부적격 검증 (보고 연기)
# 새 에러 추가
{
    printf '2026-07-10 12:07:00,000 [ERROR] app.main - Defer error\n'
} >> "$log_file"

# select-llm이 none을 반환하게 하기 위해 wrapper 강제 지정 해제
unset AUTOQAFIX_WRAPPER
# AUTOQAFIX_WRAPPERS 에 없는 래퍼들을 적어 select-llm이 none을 리턴하게 유도
export AUTOQAFIX_WRAPPERS="missingcli:paid"

# offsets.json 의 mtime 구하기
offsets_file="$HOME/.cache/autoqafix/$(python3 -c "import hashlib, pathlib; print(hashlib.sha1(str(pathlib.Path('$work').resolve()).encode()).hexdigest()[:12])")/offsets.json"
before_mtime=$(stat -c %Y "$offsets_file" 2>/dev/null || stat -f %m "$offsets_file")

# 실행
output_defer=$(uv -q run "$ERROR_TO_AUTOFIX" --repo "$work")
after_mtime=$(stat -c %Y "$offsets_file" 2>/dev/null || stat -f %m "$offsets_file")

if [[ "$output_defer" == *"보고 연기"* ]]; then
    pass "Select-llm none returns '보고 연기' successfully"
else
    fail "Select-llm none output expected '보고 연기', got: $output_defer"
fi

if [ "$before_mtime" -eq "$after_mtime" ]; then
    pass "offsets.json was not updated during defer (dry-run only)"
else
    fail "offsets.json was updated during defer"
fi

# 7. 에러 7종을 심었을 때 top5만 보고
# 정상 유료 환경 복구
export AUTOQAFIX_WRAPPER="claudecli"
export AUTOQAFIX_WRAPPERS="claudecli:paid"
# 가짜 래퍼 응답 설정
cat > "$fake_response" << 'EOF'
# autofix-3: Top 5 test
TIER: local-ok
EOF

# 에러 7종을 각각 다른 dedup_key가 되도록 추가
# 정규화 시 숫자는 #로 치환되므로 텍스트 문자를 다르게 구성해야 함.
printf '2026-07-10 12:08:01,000 [ERROR] app.worker - ErrorA %d\n' "1" >> "$log_file"
printf '2026-07-10 12:08:02,000 [ERROR] app.worker - ErrorB %d\n' "2" >> "$log_file"
printf '2026-07-10 12:08:03,000 [ERROR] app.worker - ErrorC %d\n' "3" >> "$log_file"
printf '2026-07-10 12:08:04,000 [ERROR] app.worker - ErrorD %d\n' "4" >> "$log_file"
printf '2026-07-10 12:08:05,000 [ERROR] app.worker - ErrorE %d\n' "5" >> "$log_file"
printf '2026-07-10 12:08:06,000 [ERROR] app.worker - ErrorF %d\n' "6" >> "$log_file"
printf '2026-07-10 12:08:07,000 [ERROR] app.worker - ErrorG %d\n' "7" >> "$log_file"

# 실행 전 커밋 개수 확인
before_count=$(git -C "$work" log --oneline | wc -l)
uv -q run "$ERROR_TO_AUTOFIX" --repo "$work"
git -C "$work" pull -q origin main
after_count=$(git -C "$work" log --oneline | wc -l)
diff_count=$((after_count - before_count))

# 7종 중 top 5개만 보고되었어야 하므로, 커밋 개수 차이는 10이어야 함 (예약 커밋 5개 + 완료 커밋 5개)
if [ "$diff_count" -eq 10 ]; then
    pass "Only top 5 errors reported out of 7 (10 commits generated)"
else
    fail "Expected 10 new commits for 5 reports, got: $diff_count"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-13 acceptance checks passed."
    exit 0
else
    echo "One or more issue-13 acceptance checks failed."
    exit 1
fi
