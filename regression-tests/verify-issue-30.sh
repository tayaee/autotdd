#!/usr/bin/env bash
# Verifies issue-30: doctor verify 보강 묶음 + deploy glob 의도 명시
# - check_deploy glob 의도 주석 (deploy-to-<env>.{sh,ps1,bat} 감지, env=환경명)
# - 5개 신규 분기 케이스 (deploy-to-dev.sh 단독 / select-llm none /
#   select-llm.py 부재 / .ps1 단독 래퍼 / .bat pause 비대칭)
# - verify-issue-20.sh TEST 8의 TEST 5 out_ok 재사용 범위 주석
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
DOCTOR_PY="$SKILL_DIR/autoqafix-doctor.py"
DOCTOR_BAT="$REPO_ROOT/autoqafix-doctor.bat"
VERIFY_20="$REPO_ROOT/regression-tests/verify-issue-20.sh"

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

run_doctor() {
    local dir="$1"; shift
    python3 "$DOCTOR_PY" --repo "$dir" "$@" 2>&1
}

# ===== 0. 정적 주석 검증 (요구사항 1·3) =====

# (a) check_deploy 함수 영역(def ~ 다음 def) 안에 "deploy-to-<env>"가 명시되어야 한다.
# docstring은 """ ... """ 안에 있어 일반 # 주석이 아니므로 함수 전체 줄을 본다.
if awk '
    /def check_deploy\(/ { in_fn=1; print NR": "$0; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print NR": "$0 }
' "$DOCTOR_PY" | grep -q "deploy-to-<env>"; then
    pass "check_deploy: deploy-to-<env> glob intent present"
else
    fail "check_deploy: 'deploy-to-<env>' intent not documented in function"
fi

# (b) 같은 함수 영역에 "환경명"이 명시되어야 한다.
if awk '
    /def check_deploy\(/ { in_fn=1; next }
    in_fn && /^def / { in_fn=0 }
    in_fn { print }
' "$DOCTOR_PY" | grep -q "환경명"; then
    pass "check_deploy: 환경명 플레이스홀더 명시"
else
    fail "check_deploy: '환경명' 단어가 의도 주석에 없음"
fi

# (c) verify-issue-20.sh TEST 8에 TEST 5의 out_ok 재사용 범위 주석이 있어야 한다.
# TEST 8 영역의 `#` 주석 안에 "out_ok"와 "TEST 5" 또는 "재사용"이 모두 등장해야 함.
# (코드 라인의 `$out_ok`는 제외 — 순수 주석만 본다.)
if awk '
    /^# 8\./ { in_test=1; next }
    in_test && /^# [0-9]+\./ && !/^# 8\./ { in_test=0 }
    in_test && /^#/ { print }
' "$VERIFY_20" | grep -q "out_ok" \
   && awk '
    /^# 8\./ { in_test=1; next }
    in_test && /^# [0-9]+\./ && !/^# 8\./ { in_test=0 }
    in_test && /^#/ { print }
' "$VERIFY_20" | grep -qE "TEST 5|재사용"; then
    pass "verify-issue-20.sh TEST 8: out_ok reuse scope noted"
else
    fail "verify-issue-20.sh TEST 8: out_ok 재사용 범위 주석(# 코멘트) 없음"
fi

# ===== 픽스처 공통 =====
fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

# doctor 통과용 deploy.sh
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

# ===== 1. deploy-to-dev.sh 단독 → OK deploy 스크립트 =====
# 일반 deploy.sh를 제거하고 deploy-to-dev.sh만 둔다.
rm -f "$work/deploy.sh"
cat > "$work/deploy-to-dev.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy to dev"
EOF
chmod +x "$work/deploy-to-dev.sh"

set +e
out_a="$(run_doctor "$work")"
rc_a=$?
set -e

if [ "$rc_a" -eq 0 ] && echo "$out_a" | grep -q "^OK deploy 스크립트$"; then
    pass "Case A (deploy-to-dev.sh only): OK deploy 스크립트"
else
    fail "Case A: expected exit 0 + 'OK deploy 스크립트', got exit $rc_a, output: $out_a"
fi

# ===== 2. select-llm (none) → OK select-llm (none) =====
# 다음 픽스처 케이스로 가기 전 deploy.sh 복원 (다른 케이스 영향 차단)
rm -f "$work/deploy-to-dev.sh"
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

mkdir -p "$work/wrappers"
cat > "$work/wrappers/fakecli.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake ok"
EOF
chmod +x "$work/wrappers/fakecli.sh"

# 가용 래퍼 0 시나리오: 실제 usage 스크립트가 없는 후보 + 주입된 unavailable 데이터.
# usage-fakecli.py가 없으므로 doctor의 check_usage_scripts는 FAIL만 내고
# AUTOQAFIX_USAGE_DATA_FAKECLI를 덮어쓰지 않는다 → select-llm이 'none'을 출력.
export AUTOQAFIX_WRAPPER_DIR="$work/wrappers"
export AUTOQAFIX_WRAPPERS="fakecli:paid"
export AUTOQAFIX_USAGE_DATA_FAKECLI='{"available": false, "five_hour_remaining_pct": 0, "weekly_remaining_pct": 0, "effective_remaining_pct": 0}'
unset AUTOQAFIX_WRAPPER

set +e
out_b="$(run_doctor "$work")"
rc_b=$?
set -e

if echo "$out_b" | grep -q "^OK select-llm (none)$"; then
    pass "Case B (가용 래퍼 0): OK select-llm (none)"
else
    fail "Case B: expected 'OK select-llm (none)', got exit $rc_b, output: $out_b"
fi

unset AUTOQAFIX_WRAPPER_DIR AUTOQAFIX_WRAPPERS AUTOQAFIX_USAGE_DATA_FAKECLI

# ===== 3. select-llm.py 부재 → 크래시 없이 FAIL select-llm =====
# doctor.py를 별도 임시 디렉토리로 복사 → 거기엔 select-llm.py가 없음.
fake_home="$(mktemp -d)"
CLEANUP+=("$fake_home")
mkdir -p "$fake_home/.claude/skills/autoqafix"
cp "$DOCTOR_PY" "$fake_home/.claude/skills/autoqafix/"
cp "$SKILL_DIR/autoqafix_core.py" "$fake_home/.claude/skills/autoqafix/"
# select-llm.py는 의도적으로 복사하지 않음

# preflight가 .claude/skills 안의 다른 스킬들을 검사하므로 더미 디렉토리 필요
for s in autotdd tdd2 aacpd tdd; do
    mkdir -p "$fake_home/.claude/skills/$s"
done

# doctor가 가리키는 SCRIPT_DIR은 autoqafix-doctor.py가 있는 디렉토리이므로
# 그 경로에 select-llm.py가 없으면 그대로 부재 시나리오가 된다.
export HOME="$fake_home"

set +e
out_c="$(python3 "$fake_home/.claude/skills/autoqafix/autoqafix-doctor.py" --repo "$work" 2>&1)"
rc_c=$?
set -e

unset HOME

if echo "$out_c" | grep -q "Traceback"; then
    fail "Case C (select-llm.py 부재): Python traceback 발생 — output: $out_c"
else
    pass "Case C: no Python traceback"
fi
if echo "$out_c" | grep -q "^FAIL select-llm$"; then
    pass "Case C: FAIL select-llm reported"
else
    fail "Case C: 'FAIL select-llm' 누락 — output: $out_c"
fi
if [ "$rc_c" -ge 1 ]; then
    pass "Case C: exit code >= 1 (got $rc_c)"
else
    fail "Case C: expected exit >= 1, got $rc_c — output: $out_c"
fi

# ===== 4. .ps1 단독 래퍼 → OK 래퍼 <name> =====
rm -rf "$work/wrappers"
mkdir -p "$work/wrappers"
# claudecli.sh / claudecli.bat 둘 다 만들지 않고 claudecli.ps1만 둔다.
cat > "$work/wrappers/claudecli.ps1" <<'EOF'
Write-Output "ps1 wrapper"
EOF

export AUTOQAFIX_WRAPPER_DIR="$work/wrappers"
export AUTOQAFIX_WRAPPERS="claudecli:paid"
# usage-claudecli.py는 정상 → available=true 데이터로 select-llm이 claudecli 선택
unset AUTOQAFIFIX_USAGE_DATA_CLAUDECLI  # typo-safe: 실제 키는 아래 줄
unset AUTOQAFIX_USAGE_DATA_CLAUDECLI
unset AUTOQAFIX_WRAPPER

set +e
out_d="$(run_doctor "$work")"
rc_d=$?
set -e

if echo "$out_d" | grep -q "^OK 래퍼 claudecli$"; then
    pass "Case D (.ps1 단독 래퍼): OK 래퍼 claudecli"
else
    fail "Case D: expected 'OK 래퍼 claudecli', got exit $rc_d, output: $out_d"
fi

unset AUTOQAFIX_WRAPPER_DIR AUTOQAFIX_WRAPPERS

# ===== 5. .bat pause 비대칭 — PASS 경로에 pause 없음, 오류 분기에만 있음 =====
# 단순 `grep -q pause`로는 부족하므로 awk로 paren depth를 추적하여
# 각 `pause` 라인이 반드시 if (...) 블록 내부(depth >= 1)에 있는지 검증한다.
if awk '
    BEGIN { depth = 0 }
    {
        line = $0
        # 이 줄에 등장하는 "(" 와 ")" 개수를 센다 (따옴표 안은 단순 무시 — .bat 한정)
        opens = gsub(/\(/, "&", line)
        # gsub가 원본을 바꾸므로 별도 카피에서 처리
        copy = $0
        gsub(/\(/, "", copy)
        closes_in_orig = length($0) - length(copy)
        copy = $0
        gsub(/\)/, "", copy)
        opens_in_orig = length($0) - length(copy)
        depth += opens_in_orig - closes_in_orig
        if (match($0, /\<pause\>/) || match($0, /[[:space:]]pause[[:space:]]/)) {
            if (depth < 1) {
                printf("OUTSIDE: line %d: %s\n", NR, $0) > "/tmp/_pause_check_out"
                exit 1
            }
        }
    }
    END { exit 0 }
' "$DOCTOR_BAT"; then
    pass "Case E (.bat pause 비대칭): 모든 'pause'는 if 블록 내부"
else
    pause_out="$(cat /tmp/_pause_check_out 2>/dev/null || true)"
    rm -f /tmp/_pause_check_out
    fail "Case E: 'pause'가 if 블록 외부에 위치 — ${pause_out}"
fi

# 추가 회귀 잠금: pause 라인 수 == if %ERRORLEVEL%/%EXIT_VAL% neq 0 블록 수
pause_count=$(grep -cE '^\s*pause\s*$' "$DOCTOR_BAT" || true)
if_block_count=$(grep -cE '^\s*if\s+%[A-Z_]+%\s+neq\s+0\s+\(' "$DOCTOR_BAT" || true)
if [ "$pause_count" -eq "$if_block_count" ] && [ "$pause_count" -ge 1 ]; then
    pass "Case E: pause($pause_count) == if-neq-0 blocks($if_block_count)"
else
    fail "Case E: pause=$pause_count vs if-neq-0=$if_block_count — 비대칭 의심"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-30 acceptance checks passed."
    exit 0
else
    echo "One or more issue-30 acceptance checks failed."
    exit 1
fi