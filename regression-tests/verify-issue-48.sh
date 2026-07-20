#!/usr/bin/env bash
# verify-issue-48.sh — fixing 파생 이슈에 <finding-slug> + __BY-<...> 추가 검증
# (V3 3개 층: bash grep + pytest + helper CLI 시뮬레이션)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/docs/spec/spec-issue-filenames.md"
SKILL="$REPO_ROOT/.claude/skills/autotddreviewfix/SKILL.md"
SCRIPT="$REPO_ROOT/tools/derive_fixing_slug.py"
TEST="$REPO_ROOT/tests/test_derive_fixing_slug.py"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# =========================================================================== #
# 1. 존재 확인
# =========================================================================== #
for f in "$SPEC" "$SKILL" "$SCRIPT" "$TEST"; do
    if [ -f "$f" ]; then
        pass "존재: $(basename "$f")"
    else
        fail "부재: $f"
    fi
done

# =========================================================================== #
# 2. spec 보강 — bash grep 단언
# =========================================================================== #
spec_has() { # $1=pattern $2=desc
    if grep -qF -e "$1" "$SPEC" 2>/dev/null; then
        pass "spec: $2"
    else
        fail "spec 누락: $2 (pattern: $1)"
    fi
}

spec_has "finding-slug" "finding 슬러그 컨셉"
spec_has "tools/derive_fixing_slug" "helper 참조 (단일 정본)"
spec_has "slug:" "사람 override 헤더 규약"
spec_has "알파벳 정렬" "다중 작성자 알파벳 정렬"
spec_has "self" "BY-self 예약값 (관행)"
spec_has "레거시 불변" "merge 이전 파일 불변 정책"
spec_has "BY-gemini-qwen-sonnet" "다중 작성자 알파벳 정렬 예시"
spec_has "qwen-2" "충돌 suffix 예시"

# =========================================================================== #
# 3. SKILL.md 갱신 — bash grep 단언
# =========================================================================== #
skill_has() {
    if grep -qF -e "$1" "$SKILL" 2>/dev/null; then
        pass "SKILL: $2"
    else
        fail "SKILL 누락: $2 (pattern: $1)"
    fi
}

skill_has "tools/derive_fixing_slug" "helper 호출 명시"
skill_has "python tools/derive_fixing_slug.py slug" "slug 도출 CLI 호출"
skill_has "python tools/derive_fixing_slug.py by" "BY 정렬 CLI 호출"
skill_has "python tools/derive_fixing_slug.py suffix" "suffix CLI 호출"

# 옛 형식 단독 사용 0건 — helper 호출로 대체됨을 단언
# 옛 형식: `issues/issue-<신번호>-fixing-<N>.md` 또는 `__STATE-later` 단일 슬러그
if grep -qE '`issues/issue-<신번호>-fixing-<N>\.md`' "$SKILL" 2>/dev/null; then
    fail "SKILL: 옛 fixing-<N> 단일 슬러그 명시 잔존"
else
    pass "SKILL: 옛 fixing-<N> 단일 슬러그 명시 0건"
fi
if grep -qE 'fixing-<N>__STATE-later\.md' "$SKILL" 2>/dev/null; then
    fail "SKILL: 옛 fixing-<N>__STATE-later 단독 명시 잔존"
else
    pass "SKILL: 옛 fixing-<N>__STATE-later 단독 명시 0건"
fi

# =========================================================================== #
# 4. Python helper 자체 검증
# =========================================================================== #
if python3 -m py_compile "$SCRIPT" 2>/dev/null; then
    pass "helper py_compile 통과"
else
    fail "helper py_compile 실패"
fi

# helper가 PEP 723 인라인 메타데이터를 가지는지 (stdlib only 약속 검증)
if head -n 5 "$SCRIPT" | grep -q "/// script" \
   && head -n 5 "$SCRIPT" | grep -q "dependencies = \[\]"; then
    pass "helper PEP 723 + stdlib only"
else
    fail "helper PEP 723 또는 dependencies = [] 누락"
fi

# =========================================================================== #
# 5. pytest 실행 (V3 층 2)
# =========================================================================== #
if (cd "$REPO_ROOT" && uv run --with pytest pytest tests/test_derive_fixing_slug.py -q) >/tmp/pytest-issue-48.log 2>&1; then
    # 통과한 케이스 수가 ≥ 10인지
    pass_count=$(grep -oE '[0-9]+ passed' /tmp/pytest-issue-48.log | tail -1 | grep -oE '[0-9]+' || echo "0")
    if [ "${pass_count:-0}" -ge 10 ]; then
        pass "pytest 통과 (${pass_count} 케이스)"
    else
        fail "pytest 통과 케이스 < 10 (실제: ${pass_count:-0})"
    fi
else
    fail "pytest 실패 — log: /tmp/pytest-issue-48.log"
    tail -20 /tmp/pytest-issue-48.log >&2
fi

# =========================================================================== #
# 6. helper CLI 직접 호출 (V3 층 3) — end-to-end 시뮬레이션
# =========================================================================== #
cli_out() { python3 "$SCRIPT" "$@" 2>&1; }

# by 정렬
out=$(cli_out by --names "qwen,sonnet,gemini")
if [ "$out" = "gemini-qwen-sonnet" ]; then
    pass "CLI by: qwen,sonnet,gemini → gemini-qwen-sonnet"
else
    fail "CLI by 결과 불일치: got '$out', want 'gemini-qwen-sonnet'"
fi

# by self 제외
out=$(cli_out by --names "self,qwen")
if [ "$out" = "qwen" ]; then
    pass "CLI by: self,qwen → qwen (self 제외)"
else
    fail "CLI by self 제외 결과 불일치: got '$out', want 'qwen'"
fi

# suffix 충돌
out=$(cli_out suffix --existing "a,b" --slug "a")
if [ "$out" = "a-2" ]; then
    pass "CLI suffix: a (in a,b) → a-2"
else
    fail "CLI suffix 결과 불일치: got '$out', want 'a-2'"
fi

# suffix 3단계
out=$(cli_out suffix --existing "a,a-2,a-3" --slug "a")
if [ "$out" = "a-4" ]; then
    pass "CLI suffix: a (in a,a-2,a-3) → a-4"
else
    fail "CLI suffix 3단계 결과 불일치: got '$out', want 'a-4'"
fi

# slug stdin 자동 추출
out=$(printf "### Finding: Credential exposure in error path\n\nbody" | cli_out slug)
if [ "$out" = "credential-exposure-in-error-path" ]; then
    pass "CLI slug: 자동 추출"
else
    fail "CLI slug 자동 추출 불일치: got '$out'"
fi

# slug stdin override 우선
out=$(printf "### Finding: Race\n\nslug: my-custom-name\n\nbody" | cli_out slug)
if [ "$out" = "my-custom-name" ]; then
    pass "CLI slug: override 우선"
else
    fail "CLI slug override 불일치: got '$out'"
fi

# slug 정규화 (C++ race → c-race)
out=$(printf "### Finding: C++ race\n" | cli_out slug)
if [ "$out" = "c-race" ]; then
    pass "CLI slug: 정규화 (C++ → c)"
else
    fail "CLI slug 정규화 불일치: got '$out'"
fi

# =========================================================================== #
if [ $FAIL -eq 0 ]; then
    echo "All issue-48 acceptance checks passed."
    exit 0
else
    echo "One or more issue-48 acceptance checks failed."
    exit 1
fi