#!/usr/bin/env bash
# verify-issue-39.sh — 파일명 규약 v2 전면 교체 검증
# spec 문서 존재·내용, 4 SKILL.md의 신규 태그 문법·구 문자열 부재,
# autoqafix 파이썬 2건의 태그 로직, docs 2건 갱신을 단언한다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills"
SPEC="$REPO_ROOT/docs/spec/spec-issue-filenames.md"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. spec 문서 존재 및 핵심 내용 -----
if [ -f "$SPEC" ]; then
    pass "spec 문서 존재"
else
    fail "spec 문서 부재: $SPEC"
fi

spec_has() { # $1=pattern(F고정) $2=desc
    if grep -qF -e "$1" "$SPEC" 2>/dev/null; then
        pass "spec: $2"
    else
        fail "spec에 누락: $2 (pattern: $1)"
    fi
}

spec_has "__TYPE-" "TYPE 태그"
spec_has "__STATE-" "STATE 태그"
spec_has "__BY-" "BY 태그"
spec_has "code-review" "TYPE 값 code-review"
spec_has "refix-plan" "TYPE 값 refix-plan"
spec_has "agent-failed" "STATE 값 agent-failed"
spec_has "TYPE도 STATE도 없으면" "pending 판정 규칙 한 줄"
spec_has "upgrade-issue-filenames.sh" "가드의 upgrade 스크립트 안내"
spec_has "포함되는 것만으로는 차단하지 않는다" "가드는 구조 매치 한정(포함 매치 금지)"
spec_has "상호 배타" "엄격성: TYPE⊕STATE 상호 배타"
spec_has "영문자로 시작" "엄격성: 슬러그 영문자 시작"
spec_has "닫힌 집합" "엄격성: KEY 닫힌 집합"
spec_has "예약값" "엄격성: BY-self 예약값"
spec_has "fixing-<" "파생 슬러그 관행 fixing-<M>"
spec_has "review-stats" "md 외 확장자(review-stats.json) 확장 명기"
spec_has "review-result" "레거시 review-result 불변 규칙"

# ----- 2. SKILL.md 4종: 신규 문법 존재 -----
skill_has() { # $1=skill $2=pattern $3=desc
    if grep -qF -e "$2" "$SKILL_DIR/$1/SKILL.md" 2>/dev/null; then
        pass "$1: $3"
    else
        fail "$1/SKILL.md에 누락: $3 (pattern: $2)"
    fi
}

for s in tdd2 autotdd acpd; do
    skill_has "$s" "__STATE-" "STATE 태그 서술"
    skill_has "$s" "spec-issue-filenames" "spec 정본 참조"
done
for s in tdd2 autotdd; do
    skill_has "$s" "upgrade-issue-filenames.sh" "예약 슬러그 가드(upgrade 안내)"
done
skill_has autotddreview "__TYPE-code-review__BY-" "리뷰 파일명 태그"
skill_has autotddreview "__BY-self" "셀프 리뷰 BY-self"
skill_has autotddreview "__TYPE-refix-plan" "refix-plan 파일명"

# ----- 3. SKILL.md 4종: 구 문자열 부재 -----
for s in tdd2 autotdd acpd autotddreview; do
    f="$SKILL_DIR/$s/SKILL.md"
    if grep -qE '(\*|[0-9#N>])-(later|manual|agent-failed)\.md' "$f" 2>/dev/null; then
        fail "$s: 구 파킹 접미사 문자열 잔존"
    else
        pass "$s: 구 파킹 접미사 문자열 0건"
    fi
    if grep -q "feedback-review" "$f" 2>/dev/null; then
        fail "$s: 구 feedback-review 문자열 잔존"
    else
        pass "$s: feedback-review 0건"
    fi
    if grep -q "code-review-by-" "$f" 2>/dev/null; then
        fail "$s: 구 code-review-by- 문자열 잔존"
    else
        pass "$s: code-review-by- 0건"
    fi
done

# ----- 4. autoqafix 파이썬 2건: 태그 로직 교체 -----
AF="$SKILL_DIR/autoqafix/autofix.py"
EA="$SKILL_DIR/autoqafix/error-to-autofix.py"

grep -qF '__STATE-manual' "$AF" && pass "autofix.py: __STATE-manual" || fail "autofix.py: __STATE-manual 누락"
grep -qF '__STATE-agent-failed' "$AF" && pass "autofix.py: __STATE-agent-failed" || fail "autofix.py: __STATE-agent-failed 누락"
grep -qF '__STATE-manual' "$EA" && pass "error-to-autofix.py: __STATE-manual" || fail "error-to-autofix.py: __STATE-manual 누락"

if grep -qE '\}-(manual|agent-failed)\.md' "$AF" "$EA" 2>/dev/null; then
    fail "파이썬: 구 접미사 rename 로직 잔존"
else
    pass "파이썬: 구 접미사 rename 로직 0건"
fi
if grep -qE '"\-(later|manual|agent-failed)"' "$AF" 2>/dev/null; then
    fail "autofix.py: 구 SUFFIXES 튜플 잔존"
else
    pass "autofix.py: 구 SUFFIXES 튜플 0건"
fi

# 파이썬 문법 검사
if python3 -m py_compile "$AF" "$EA" 2>/dev/null; then
    pass "파이썬 2건 py_compile 통과"
else
    fail "파이썬 py_compile 실패"
fi

# ----- 5. docs 2건 갱신 -----
for d in SETUP-autoqafix.md autoqafix-design.md; do
    f="$REPO_ROOT/docs/$d"
    grep -qF '__STATE-manual' "$f" && pass "docs/$d: __STATE-manual" || fail "docs/$d: __STATE-manual 누락"
    if grep -qF '`-manual`' "$f" 2>/dev/null; then
        fail "docs/$d: 구 접미사 표기 잔존"
    else
        pass "docs/$d: 구 접미사 표기 0건"
    fi
done

if [ $FAIL -eq 0 ]; then
    echo "All issue-39 acceptance checks passed."
    exit 0
else
    echo "One or more issue-39 acceptance checks failed."
    exit 1
fi
