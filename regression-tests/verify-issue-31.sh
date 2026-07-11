#!/usr/bin/env bash
# Verifies issue-31: doctor 계약·문서화 정리 — 폴백 정책, preflight 메시지
# 계약, design.md doctor 절.
# - check_wrappers / run_pings의 비대칭 의도 주석 (각 함수 docstring 안에)
# - preflight() docstring에 메시지 계약 ("[원인] ...\n[조치] ..." 2줄) 명시
# - fail_preformatted docstring이 preflight 계약 docstring을 상호 참조
# - docs/autoqafix-design.md에 "진단 (autoqafix-doctor)" 절 존재
# - doctor 모듈 docstring에 preflight role 단위 FAIL 계수 1줄 명시
# - 기존 doctor 스모크 회귀 1회 (픽스처 exit 0)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
DOCTOR_PY="$SKILL_DIR/autoqafix-doctor.py"
CORE_PY="$SKILL_DIR/autoqafix_core.py"
DESIGN_MD="$REPO_ROOT/docs/autoqafix-design.md"

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

# 함수 영역(다음 def/class 전까지) 안에서만 검색하는 awk 헬퍼.
extract_fn() {
    local fn_pattern="$1"
    awk -v pat="$fn_pattern" '
        $0 ~ pat && $0 ~ /^def[[:space:]]/ { in_fn=1; next }
        in_fn && /^def[[:space:]]/ && $0 !~ pat { in_fn=0 }
        in_fn { print }
        END { }
    ' "$DOCTOR_PY"
}

# ===== 1. design.md에 doctor 절 존재 =====

if grep -E '^## 진단 \(autoqafix-doctor\)' "$DESIGN_MD" >/dev/null; then
    pass "design.md: 진단 (autoqafix-doctor) 절 헤더 존재"
else
    fail "design.md: '## 진단 (autoqafix-doctor)' 헤더 없음"
fi

# 7항목 검사 키워드가 design.md doctor 절 안에 모두 등장해야 한다.
# awk로 절 단위로 잘라낸 뒤 검사한다.
doctor_section="$(awk '
    /^## 진단 \(autoqafix-doctor\)/ { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    in_sec { print }
' "$DESIGN_MD")"

for kw in "preflight" "래퍼 존재" "usage 스크립트" "select-llm" "deploy 스크립트" "뮤텍스 잠금" "필수 스킬" "peek_lock" "is_lock_reclaimable" "acquire_lock"; do
    if echo "$doctor_section" | grep -qF "$kw"; then
        pass "design.md doctor 절 키워드 존재: $kw"
    else
        fail "design.md doctor 절에 '$kw' 없음"
    fi
done

# `--ping`은 grep에 옵션으로 오해되므로 별도로 -- 처리해서 검색.
if echo "$doctor_section" | grep -qF -- "--ping"; then
    pass "design.md doctor 절 키워드 존재: --ping"
else
    fail "design.md doctor 절에 '--ping' 없음"
fi

# ===== 2. preflight() docstring에 메시지 계약 =====

if awk '
    /def preflight\(/ { in_fn=1; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print }
' "$CORE_PY" | grep -q '\[원인\]'; then
    pass "preflight() docstring: [원인] 포맷 명시"
else
    fail "preflight() docstring: '[원인]' 포맷 미명시"
fi
if awk '
    /def preflight\(/ { in_fn=1; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print }
' "$CORE_PY" | grep -q '\[조치\]'; then
    pass "preflight() docstring: [조치] 포맷 명시"
else
    fail "preflight() docstring: '[조치]' 포맷 미명시"
fi
# '2줄' / '두 줄' / '2-줄' 같은 표기 중 하나가 있어야 계약 문구로 인정.
if awk '
    /def preflight\(/ { in_fn=1; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print }
' "$CORE_PY" | grep -qE '2줄|두 줄'; then
    pass "preflight() docstring: 2줄 계약 문구 존재"
else
    fail "preflight() docstring: '2줄' / '두 줄' 문구 없음"
fi

# ===== 3. fail_preformatted docstring이 preflight 계약 docstring을 상호 참조 =====

fp_doc="$(awk '
    /def fail_preformatted/ { in_fn=1; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print }
' "$DOCTOR_PY")"

if echo "$fp_doc" | grep -q "preflight"; then
    pass "fail_preformatted docstring: preflight 참조 존재"
else
    fail "fail_preformatted docstring: 'preflight' 단어 없음 — preflight docstring과의 상호 참조가 약함"
fi
if echo "$fp_doc" | grep -q "autoqafix_core"; then
    pass "fail_preformatted docstring: autoqafix_core 모듈 경로 명시"
else
    fail "fail_preformatted docstring: 'autoqafix_core' 모듈 경로 명시 없음"
fi

# ===== 4. doctor 모듈 docstring: preflight role 단위 FAIL 계수 1줄 =====

# 모듈 docstring은 파일 첫 번째 """ ... """ 블록. awk로 추출.
module_doc="$(awk '
    /^"""/ { count++; in_doc = (count % 2 == 1); next }
    in_doc { print }
' "$DOCTOR_PY")"

if echo "$module_doc" | grep -q "preflight"; then
    pass "doctor 모듈 docstring: preflight 언급 존재"
else
    fail "doctor 모듈 docstring: 'preflight' 단어 없음"
fi
if echo "$module_doc" | grep -qE "FAIL 계수|Fail|fail"; then
    pass "doctor 모듈 docstring: FAIL 계수 설명 존재"
else
    fail "doctor 모듈 docstring: FAIL 계수 설명 없음"
fi

# ===== 5. check_wrappers 의도 주석 (비대칭 이유) =====

cw_doc="$(extract_fn 'def check_wrappers')"

if echo "$cw_doc" | grep -qE "비대칭|경로 결정"; then
    pass "check_wrappers: 비대칭 / 경로 결정 의도 문구 존재"
else
    fail "check_wrappers: 비대칭 / 경로 결정 의도 문구 없음"
fi
if echo "$cw_doc" | grep -qE "PATH"; then
    pass "check_wrappers: PATH 폴백 언급 존재"
else
    fail "check_wrappers: PATH 폴백 언급 없음"
fi

# ===== 6. run_pings 의도 주석 (비대칭 이유) =====

rp_doc="$(extract_fn 'def run_pings')"

if echo "$rp_doc" | grep -qE "비대칭|경로 결정"; then
    pass "run_pings: 비대칭 / 경로 결정 의도 문구 존재"
else
    fail "run_pings: 비대칭 / 경로 결정 의도 문구 없음"
fi
# "PATH 폴백은 두지 않는다" / "PATH 폴백 없음" 같은 명시적 문구 필요.
if echo "$rp_doc" | grep -qE "PATH (폴백|없음|미사용|두지 않)"; then
    pass "run_pings: PATH 폴백 미사용 명시"
else
    fail "run_pings: 'PATH 폴백 두지 않는다' 류 명시 없음"
fi

# ===== 7. 기존 doctor 스모크 회귀 (픽스처 exit 0) =====

fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

set +e
out="$(python3 "$DOCTOR_PY" --repo "$work" 2>&1)"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
    pass "기존 doctor 스모크: 픽스처 exit 0"
else
    fail "기존 doctor 스모크: exit $rc — output: $out"
fi
if echo "$out" | grep -q "^진단 완료: FAIL 0건$"; then
    pass "기존 doctor 스모크: FAIL 0건 종료 메시지"
else
    fail "기존 doctor 스모크: '진단 완료: FAIL 0건' 종료 줄 없음 — output: $out"
fi

# ===== 요약 =====

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-31 acceptance checks passed."
    exit 0
else
    echo "One or more issue-31 acceptance checks failed."
    exit 1
fi
