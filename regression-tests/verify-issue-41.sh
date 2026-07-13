#!/usr/bin/env bash
# verify-issue-41.sh — autotddreview 플래너 이중 게이트 + 파생 이슈 생성·파킹 +
# review-stats JSON 기록 검증 (SKILL.md 정적 단언)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

has() {
    if grep -qF -e "$1" "$SKILL" 2>/dev/null; then
        pass "$2"
    else
        fail "누락: $2 (pattern: $1)"
    fi
}

# 형식 게이트
has "증거 미비" "형식 게이트: 증거 미비 자동 reject"
# must-fix 실질 재검증
has "재검증" "must-fix 한정 실질 재검증"
has "인용이 실재" "재검증: 인용 실재 확인"
has "주장이 성립" "재검증: 주장 성립 확인"
# 파생 이슈 생성
has "-fixing-<N>" "파생 이슈 파일명 -fixing-<N>"
has "__STATE-later" "good-to-fix 파킹 (__STATE-later)"
has "최대 번호 + 1" "채번: 아카이브 포함 max+1"
has "계보" "본문 계보 필수"
# refix-plan
has "__TYPE-refix-plan" "refix-plan 산출"
has "재검증 실패" "reject 사유 구분(증거 미비/재검증 실패)"
# agent-stats JSON (issue-47: review-stats.json + coding-stats.json 통합)
has "__TYPE-agent-stats.json" "agent-stats JSON 기록"
for field in findings gate_rejected verify_rejected must_fix good_to_fix; do
    has "$field" "agent-stats 필드: $field"
done
# Step 4
has "pending" "Step 4: pending 파생 이슈만 처리"
has "건드리지 않는다" "Step 4: 파킹 불가침"

# 구 용어 부재
if grep -q "feedback-review" "$SKILL" 2>/dev/null; then
    fail "구 feedback-review 문자열 잔존"
else
    pass "feedback-review 0건"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-41 acceptance checks passed."
    exit 0
else
    echo "One or more issue-41 acceptance checks failed."
    exit 1
fi
