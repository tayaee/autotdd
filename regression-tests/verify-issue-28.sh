#!/usr/bin/env bash
# Verifies issue-28: doctor 스킬 검사 중복 FAIL dedupe
# - preflight(fix)가 이미 {autotdd,tdd2,acpd} 부재를 보고하므로
#   check_skills()는 해당 3종에 대해 FAIL을 중복 계수해서는 안 됨.
# - tdd(중복되지 않는 마지막 스킬)만 check_skills()에서 FAIL 계수.
# - 4종 모두 정상일 때 OK 스킬 <name> 4줄 출력 유지.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
DOCTOR_PY="$SKILL_DIR/autoqafix-doctor.py"

FAIL=0
CLEANUP=()
CLEANUP_FILES=()

cleanup() {
    for d in "${CLEANUP[@]:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
    done
    for f in "${CLEANUP_FILES[@]:-}"; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
    done
}
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# 픽스처 저장소 생성 (git/logs/issues/src 모두 포함)
fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

# deploy.sh 생성 (doctor의 deploy 검사 통과 보장)
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

run_doctor() {
    local dir="$1"; shift
    python3 "$DOCTOR_PY" --repo "$dir" "$@" 2>&1
}

# 래퍼 검사를 우회하여 doctor 출력을 스킬 관련 FAIL에만 집중시키기 위해
# AUTOQAFIX_WRAPPERS=","로 빈 사양을 명시한다.
export AUTOQAFIX_WRAPPERS=","

# 픽스처 HOME 생성 헬퍼
make_fake_home() {
    local missing_skill="${1:-}"
    local fake_home
    fake_home="$(mktemp -d)"
    CLEANUP+=("$fake_home")
    mkdir -p "$fake_home/.claude/skills"
    # 4종 모두 설치한 뒤 누락시킬 것만 제거
    for s in autotdd tdd2 acpd tdd; do
        mkdir -p "$fake_home/.claude/skills/$s"
    done
    if [ -n "$missing_skill" ]; then
        rm -rf "$fake_home/.claude/skills/$missing_skill"
    fi
    echo "$fake_home"
}

# ----- 시나리오 1: preflight가 검사하는 3종 중 1종 부재(tdd2) → FAIL 1건 -----
fake_home1="$(make_fake_home tdd2)"
HOME="$fake_home1" run_doctor "$work" > "$fixture/out1.txt" 2>&1
out1="$(cat "$fixture/out1.txt")"

fail_lines_1="$(echo "$out1" | grep -c '^FAIL ' || true)"
ok_skill_lines_1="$(echo "$out1" | grep -c '^OK 스킬 ' || true)"
exit_1="$(HOME="$fake_home1" python3 "$DOCTOR_PY" --repo "$work" >/dev/null 2>&1; echo $?)"

if [ "$fail_lines_1" -eq 1 ]; then
    pass "Scenario 1 (tdd2 부재): FAIL 줄 1건 (got $fail_lines_1)"
else
    fail "Scenario 1 (tdd2 부재): FAIL 줄 1건이어야 하나 $fail_lines_1건 — output: $out1"
fi
if [ "$exit_1" -eq 1 ]; then
    pass "Scenario 1 (tdd2 부재): exit code = 1"
else
    fail "Scenario 1 (tdd2 부재): exit code = 1이어야 하나 $exit_1 — output: $out1"
fi
# 부재 스킬(tdd2)이 출력에 한 번만 등장해야 함 (preflight 또는 check_skills 한 곳)
tdd2_mentions="$(echo "$out1" | grep -c 'tdd2' || true)"
if [ "$tdd2_mentions" -eq 1 ]; then
    pass "Scenario 1 (tdd2 부재): tdd2 메시지 1회만 출력 (중복 회피 OK)"
else
    fail "Scenario 1 (tdd2 부재): tdd2 메시지 $tdd2_mentions회 — 중복 출력됨 — output: $out1"
fi
# 출력 본문도 저장 (디버깅용)
echo "--- [Scenario 1 output] ---"
echo "$out1"
echo "---"

# ----- 시나리오 2: 4종 모두 정상 → OK 스킬 4줄, FAIL 0 -----
fake_home2="$(make_fake_home)"
HOME="$fake_home2" run_doctor "$work" > "$fixture/out2.txt" 2>&1
out2="$(cat "$fixture/out2.txt")"

ok_skill_lines_2="$(echo "$out2" | grep -c '^OK 스킬 ' || true)"
fail_lines_2="$(echo "$out2" | grep -c '^FAIL ' || true)"
ok_skill_names="$(echo "$out2" | grep '^OK 스킬 ' | sort)"

if [ "$ok_skill_lines_2" -eq 4 ]; then
    pass "Scenario 2 (4종 정상): OK 스킬 4줄 (got $ok_skill_lines_2)"
else
    fail "Scenario 2 (4종 정상): OK 스킬 4줄이어야 하나 $ok_skill_lines_2줄 — output: $out2"
fi
if [ "$fail_lines_2" -eq 0 ]; then
    pass "Scenario 2 (4종 정상): FAIL 0건"
else
    fail "Scenario 2 (4종 정상): FAIL $fail_lines_2건 (회귀) — output: $out2"
fi
expected_names=$(printf 'OK 스킬 acpd\nOK 스킬 autotdd\nOK 스킬 tdd\nOK 스킬 tdd2\n' | sort)
got_names="$(echo "$ok_skill_names" | sort -u)"
if [ "$got_names" = "$expected_names" ]; then
    pass "Scenario 2 (4종 정상): OK 스킬 4종 전부 출력"
else
    fail "Scenario 2 (4종 정상): OK 스킬 누락 — got: $got_names"
fi

# ----- 시나리오 3: preflight가 검사하지 않는 tdd 단독 부재 → FAIL 1건 -----
fake_home3="$(make_fake_home tdd)"
HOME="$fake_home3" run_doctor "$work" > "$fixture/out3.txt" 2>&1
out3="$(cat "$fixture/out3.txt")"

fail_lines_3="$(echo "$out3" | grep -c '^FAIL ' || true)"
exit_3="$(HOME="$fake_home3" python3 "$DOCTOR_PY" --repo "$work" >/dev/null 2>&1; echo $?)"

if [ "$fail_lines_3" -eq 1 ]; then
    pass "Scenario 3 (tdd 단독 부재): FAIL 줄 1건"
else
    fail "Scenario 3 (tdd 단독 부재): FAIL 줄 1건이어야 하나 $fail_lines_3건 — output: $out3"
fi
if [ "$exit_3" -eq 1 ]; then
    pass "Scenario 3 (tdd 단독 부재): exit code = 1"
else
    fail "Scenario 3 (tdd 단독 부재): exit code = 1이어야 하나 $exit_3 — output: $out3"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-28 acceptance checks passed."
    exit 0
else
    echo "One or more issue-28 acceptance checks failed."
    exit 1
fi