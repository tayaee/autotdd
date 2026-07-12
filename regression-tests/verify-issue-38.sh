#!/usr/bin/env bash
# Verifies issue-38: 구 스킬명 → autotddreview 개명 + 위치 인자 문법·인라인 역할 단순화
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_PATH="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"
HARNESS_DIR="/home/user1/git/harness-project"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. autotddreview/SKILL.md 존재 및 name 단언 -----
if [ -f "$SKILL_PATH" ]; then
    pass "SKILL.md 존재함"
else
    fail "SKILL.md가 $SKILL_PATH 에 존재하지 않음"
fi

if grep -q 'name:[[:space:]]*autotddreview' "$SKILL_PATH"; then
    pass "name: autotddreview 설정됨"
else
    fail "SKILL.md에 'name: autotddreview'가 없음"
fi

# ----- 2. 옛 플래그 문자열 부재 -----
for flag in "--model" "--coder" "--reviewers" "--planner"; do
    if grep -qF -e "$flag" "$SKILL_PATH"; then
        fail "옛 플래그 문자열 '$flag'가 SKILL.md에 잔존함"
    else
        pass "옛 플래그 문자열 '$flag'가 SKILL.md에 없음"
    fi
done

# ----- 3. 위치 인자, worktree, -by-self, feedback-review.md 서술 존재 -----
for keyword in "positional" "worktree" "-by-self" "feedback-review.md"; do
    if grep -qi -e "$keyword" "$SKILL_PATH"; then
        pass "SKILL.md에 '$keyword' 관련 서술 존재함"
    else
        fail "SKILL.md에 '$keyword' 관련 서술이 누락됨"
    fi
done

# ----- 4. secrets 부재 -----
if grep -qE 'MINIMAX_API_KEY=[A-Za-z0-9]|sk-[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|key-[A-Za-z0-9]{20,}' "$SKILL_PATH"; then
    fail "SKILL.md에 secret 리터럴이 존재함"
else
    pass "SKILL.md에 secret 리터럴이 없음"
fi

# ----- 5. 리포 내 구 스킬명 문자열 0건 (아카이브·과거 verify 주석 제외) -----
# git grep의 결과에서 issues/archive/ 폴더와 regression-tests/verify-issue-*.sh 파일의 주석(#)을 제외
# verify-issue-38.sh 자기 자신은 autorev""fix 라는 표현으로 우회하여 단어가 직접 포함되지 않게 함.
old_name_pattern="autorev""fix"
matches=$(git -C "$REPO_ROOT" grep -in "$old_name_pattern" 2>/dev/null | \
          grep -v "issues/archive/" | \
          grep -vE "^regression-tests/verify-issue-[0-9]+\.sh:[0-9]+:#[[:space:]]*" || true)

if [ -n "$matches" ]; then
    fail "구 스킬명 문자열이 아카이브 및 과거 verify 주석 외에 존재함: $matches"
else
    pass "구 스킬명 문자열이 아카이브 및 과거 verify 주석 외에 0건임"
fi

# ----- 6. companion (harness-project) 검사 -----
if [ -d "$HARNESS_DIR" ]; then
    pass "harness-project 디렉토리 존재함"
    
    # 파일 존재 및 실행권한 검사
    if [ -x "$HARNESS_DIR/clean-skills.sh" ]; then
        pass "clean-skills.sh 존재 및 실행 권한 있음"
    else
        fail "clean-skills.sh가 없거나 실행 권한이 없음"
    fi
    
    if [ -f "$HARNESS_DIR/clean-skills.ps1" ]; then
        pass "clean-skills.ps1 존재함"
    else
        fail "clean-skills.ps1이 존재하지 않음"
    fi

    if [ -f "$HARNESS_DIR/clean-skills.bat" ]; then
        pass "clean-skills.bat 존재함"
    else
        fail "clean-skills.bat이 존재하지 않음"
    fi

    # 3개 항목 배열 확인
    if grep -q "$old_name_pattern" "$HARNESS_DIR/clean-skills.sh" && \
       grep -q "to-issues" "$HARNESS_DIR/clean-skills.sh" && \
       grep -q "to-prd" "$HARNESS_DIR/clean-skills.sh"; then
        pass "clean-skills.sh에 3개 항목(구 스킬명, to-issues, to-prd) 존재함"
    else
        fail "clean-skills.sh에 3개 항목 중 일부가 누락됨"
    fi

    # 3겹 제거 로직 확인
    # .claude/skills, .agents/skills, .skill-lock.json 등
    if grep -q "skills" "$HARNESS_DIR/clean-skills.sh" && \
       grep -q "lock" "$HARNESS_DIR/clean-skills.sh"; then
        pass "clean-skills.sh에 3겹 제거 로직 서술 확인됨"
    else
        fail "clean-skills.sh에 3겹 제거 로직 서술이 부족함"
    fi
else
    fail "harness-project 디렉토리($HARNESS_DIR)가 존재하지 않음"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-38 acceptance checks passed."
    exit 0
else
    echo "One or more issue-38 acceptance checks failed."
    exit 1
fi
