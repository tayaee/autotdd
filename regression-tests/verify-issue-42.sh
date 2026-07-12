#!/usr/bin/env bash
# verify-issue-42.sh — autotddreview 리뷰 범위 고정 검증: Step 1 범위 캡처
# (시작 HEAD·재개 역추적·worktree), Step 2 프롬프트 범위 주입, 범위 밖 제한,
# 폴백(침묵 금지)을 SKILL.md에서 단언한다.
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

# Step 1 — 범위 캡처
has "시작HEAD" "Step 1: 시작 HEAD 기록"
has "git diff --name-only" "Step 1: 변경 파일 목록 산출"
has "역추적" "Step 1: 재개 시 커밋 역추적"
has "main 기준" "Step 1: worktree 모드 병합 후 산출"

# Step 2 — 프롬프트 주입
has "커밋 범위" "주입: 커밋 범위"
has "변경 파일 목록" "주입: 변경 파일 목록"
has "회귀 스크립트" "주입: 회귀 스크립트 경로"
has "스펙 대조" "주입: 이슈 파일(스펙 대조용)"
has "범위 밖" "제한 지시: 범위 밖 코드"
has "호출부" "제한 지시: 직접 상호작용 예외"

# 폴백
has "침묵 금지" "폴백: 범위 산출 실패 시 명시"

if [ $FAIL -eq 0 ]; then
    echo "All issue-42 acceptance checks passed."
    exit 0
else
    echo "One or more issue-42 acceptance checks failed."
    exit 1
fi
