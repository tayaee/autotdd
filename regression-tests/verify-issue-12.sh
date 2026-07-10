#!/usr/bin/env bash
# Verifies issue-12: log-scan.py tool requirements and acceptance criteria.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
LOG_SCAN="$SKILL_DIR/log-scan.py"

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

# 1. log-scan.py 존재 여부 확인
if [ ! -f "$LOG_SCAN" ]; then
    fail "missing $LOG_SCAN"
    exit 1
fi

# 2. 임시 픽스처 저장소 생성
fixture_path="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$fixture_path")
work="$fixture_path/work"

# 3. 첫 실행 (첫 관측) 검증
# 첫 관측은 "errors:[]" 이어야 하고 offsets.json이 업데이트되어야 함.
output1=$(uv -q run "$LOG_SCAN" --repo "$work")
errors_len1=$(echo "$output1" | jq '.errors | length')
if [ "$errors_len1" -eq 0 ]; then
    pass "First scan returns 0 errors (EOF initialization)"
else
    fail "First scan returned $errors_len1 errors, expected 0"
fi

# offsets.json 이 정상 생성되었는지 확인
offsets_file="$HOME/.cache/autoqafix/$(python3 -c "import hashlib, pathlib; print(hashlib.sha1(str(pathlib.Path('$work').resolve()).encode()).hexdigest()[:12])")/offsets.json"
if [ -f "$offsets_file" ]; then
    pass "offsets.json created in cache"
else
    fail "offsets.json not found in cache"
fi

# 4. 로그 파일에 새 에러 라인들을 append 한 후 재실행하여 검증
log_file="$work/logs/app.main.log"

# append traceback
{
    printf '2026-07-10 12:05:00,000 [ERROR] app.main - Another error\n'
    printf 'Traceback (most recent call last):\n'
    printf '  File "work/src/app.py", line 42, in process\n'
    printf '    result = compute(x)\n'
    printf 'ValueError: new traceback exception\n'
} >> "$log_file"

# append simple error
printf '2026-07-10 12:05:01,000 [ERROR] app.worker - Failed again\n' >> "$log_file"
printf '2026-07-10 12:05:02,000 [ERROR] app.worker - Failed again\n' >> "$log_file"

output2=$(uv -q run "$LOG_SCAN" --repo "$work")
# traceback key: tb:src/app.py:42:ValueError (count=1)
# simple error key: line:app.main.log:app.worker:<hash> (count=2)
# count 내림차순이어야 하므로 simple error가 앞선다.

# 각 에러 키의 개수 추출 검증
worker_count=$(echo "$output2" | jq -r '.errors[] | select(.dedup_key | startswith("line:app.main.log:app.worker:")) | .count')
tb_count=$(echo "$output2" | jq -r '.errors[] | select(.dedup_key == "tb:src/app.py:42:ValueError") | .count')

if [ "$worker_count" -eq 2 ]; then
    pass "Worker error count check passed (count=2)"
else
    fail "Expected worker error count 2, got: $worker_count"
fi

if [ "$tb_count" -eq 1 ]; then
    pass "Traceback error count check passed (count=1)"
else
    fail "Expected traceback error count 1, got: $tb_count"
fi

# 정렬 순서 검증 (1위는 count=2인 worker 에러여야 함)
first_key=$(echo "$output2" | jq -r '.errors[0].dedup_key')
if [[ "$first_key" == line:app.main.log:app.worker:* ]]; then
    pass "Sorting order check passed (1st is worker line error)"
else
    fail "Expected worker error as 1st element due to count, got: $first_key"
fi

# latest_ts 검증
first_ts=$(echo "$output2" | jq -r '.errors[0].latest_ts')
if [ "$first_ts" = "2026-07-10 12:05:02,000" ]; then
    pass "Latest TS check passed for simple error"
else
    fail "Expected latest TS to be 2026-07-10 12:05:02,000, got: $first_ts"
fi

# 5. WARNING만 추가 검증
{
    printf '2026-07-10 12:06:00,000 [WARNING] app.main - Warning message\n'
} >> "$log_file"
output3=$(uv -q run "$LOG_SCAN" --repo "$work")
errors_len3=$(echo "$output3" | jq '.errors | length')
if [ "$errors_len3" -eq 0 ]; then
    pass "WARNING only returns 0 errors"
else
    fail "WARNING scan returned errors: $output3"
fi

# 6. truncate 후 새 내용 기록 (새 파일 감지)
: > "$log_file"
{
    printf '2026-07-10 12:07:00,000 [ERROR] app.main - Truncated error\n'
} >> "$log_file"
output4=$(uv -q run "$LOG_SCAN" --repo "$work")
errors_len4=$(echo "$output4" | jq '.errors | length')
# truncate 되었을 때 offsets.json의 size가 offset보다 작거나 prefix_sha1이 다르면 새 파일로 감지해야 함.
# 새 파일로 감지된 경우 offset 0부터 전체 재스캔이므로, errors_len4는 1이어야 함.
if [ "$errors_len4" -eq 1 ]; then
    pass "Truncated file detected as new and scanned from offset 0"
else
    fail "Truncated scan expected 1 error, got: $output4"
fi

# 7. --dry-run 검증 (2회 연속 실행 동일, 오프셋 전진 안함)
# 새 에러 추가
printf '2026-07-10 12:08:00,000 [ERROR] app.main - Dry run error\n' >> "$log_file"
# 첫 번째 dry-run
dry_out1=$(uv -q run "$LOG_SCAN" --repo "$work" --dry-run)
# 두 번째 dry-run
dry_out2=$(uv -q run "$LOG_SCAN" --repo "$work" --dry-run)

if [ "$dry_out1" = "$dry_out2" ]; then
    pass "Dry-run outputs are identical"
else
    fail "Dry-run outputs differ"
fi

# dry-run 아닌 실제 실행 시 에러가 검출되어야 함 (offsets.json이 갱신되지 않았으므로)
real_out=$(uv -q run "$LOG_SCAN" --repo "$work")
real_errors_len=$(echo "$real_out" | jq '.errors | length')
if [ "$real_errors_len" -gt 0 ]; then
    pass "Real run after dry-run detects the errors (offset did not advance during dry-run)"
else
    fail "Real run detected no errors, indicating dry-run advanced the offset incorrectly"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-12 acceptance checks passed."
    exit 0
else
    echo "One or more issue-12 acceptance checks failed."
    exit 1
fi
