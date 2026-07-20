#!/usr/bin/env bash
# verify-issue-40.sh — autotddreviewfix 리뷰어 프롬프트 4부 구조 검증
# ① 환경 사실(.python-version→pyproject.toml, 3.12 캡) ② 범위(OWASP, 스타일·타입
# 보고 금지) ③ 증거 계약(3요소, 정밀도 우선) ④ 구조화 finding 포맷 + 셀프 리뷰
# 동일 적용 + 첫 줄 모델명 유지를 SKILL.md에서 단언한다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/.claude/skills/autotddreviewfix/SKILL.md"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

has() { # $1=fixed-string $2=desc
    if grep -qF -e "$1" "$SKILL" 2>/dev/null; then
        pass "$2"
    else
        fail "누락: $2 (pattern: $1)"
    fi
}

# ① 환경 사실
has ".python-version" "환경 사실: .python-version 해석"
has "requires-python" "환경 사실: pyproject.toml requires-python 폴백"
has "3.12" "환경 사실: 3.12 캡 규칙"
has "ruff" "환경 사실: 도구체인 통과 상태 고지"

# ② 범위
has "OWASP" "범위: OWASP Top 10 렌즈"
has "보고 금지" "범위: 스타일·타입 보고 금지"
has "동시성" "범위: 동시성·경계조건"

# ③ 증거 계약
has "실패 시나리오" "증거 계약: 실패 시나리오 필수"
has "확인 방법" "증거 계약: 확인 방법 필수"
has "코드 인용" "증거 계약: 파일:라인+코드 인용 필수"
has "누락보다 오판이 비싸다" "증거 계약: 정밀도 우선 문구"

# ④ 구조화 포맷
has "good-to-fix" "구조화 포맷: 심각도 제안 필드"
has "자유 산문" "구조화 포맷: 자유 산문 금지"

# 유지·공통 적용
has "자기 모델명(버전 포함)" "첫 줄 모델명 기입 유지"
has "셀프 리뷰" "셀프 리뷰에도 동일 구조 적용 서술"

if [ $FAIL -eq 0 ]; then
    echo "All issue-40 acceptance checks passed."
    exit 0
else
    echo "One or more issue-40 acceptance checks failed."
    exit 1
fi
