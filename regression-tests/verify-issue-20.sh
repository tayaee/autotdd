#!/usr/bin/env bash
# Verifies issue-20: autoqafix-doctor — 사전 점검 도구.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
DOCTOR_PY="$SKILL_DIR/autoqafix-doctor.py"

FAIL=0
CLEANUP=()

cleanup() {
    for d in "${CLEANUP[@]:-}"; do
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

# 1. 파일 존재: doctor py + 런처 3종
if [ ! -f "$DOCTOR_PY" ]; then
    fail "missing $DOCTOR_PY"
fi
for ext in sh ps1 bat; do
    if [ ! -f "$REPO_ROOT/autoqafix-doctor.$ext" ]; then
        fail "missing autoqafix-doctor.$ext"
    fi
done
[ "$FAIL" -eq 0 ] || exit 1

# 2. 정적 검사
if bash -n "$REPO_ROOT/autoqafix-doctor.sh"; then
    pass "bash -n autoqafix-doctor.sh passed"
else
    fail "bash -n autoqafix-doctor.sh failed"
fi
if grep -q -i "pause" "$REPO_ROOT/autoqafix-doctor.bat"; then
    pass "autoqafix-doctor.bat has 'pause'"
else
    fail "autoqafix-doctor.bat missing 'pause'"
fi

# 3. 픽스처 + 공통 env
fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

fake_dir="$(mktemp -d)"
CLEANUP+=("$fake_dir")
cp "$LIB/fake-wrapper.sh" "$fake_dir/claudecli.sh"
chmod +x "$fake_dir/claudecli.sh"

export AUTOQAFIX_WRAPPERS="claudecli:paid"
export AUTOQAFIX_WRAPPER_DIR="$fake_dir"
export AUTOQAFIX_WRAPPER="claudecli"

run_doctor() {
    local dir="$1"; shift
    (cd "$dir" && bash "$REPO_ROOT/autoqafix-doctor.sh" "$@" 2>&1)
}

# 4. deploy 스크립트 없는 픽스처: WARN은 나오되 exit에 반영 안 됨
set +e
out_warn="$(run_doctor "$work")"
rc_warn=$?
set -e

if echo "$out_warn" | grep -q "WARN — deploy 스크립트 없음"; then
    pass "no-deploy fixture: WARN line printed"
else
    fail "no-deploy fixture: WARN line missing — output: $out_warn"
fi
if [ "$rc_warn" -eq 0 ]; then
    pass "no-deploy fixture: WARN not counted in exit (exit 0)"
else
    fail "no-deploy fixture: expected exit 0, got $rc_warn — output: $out_warn"
fi

# 5. 완전한 픽스처: FAIL 0, exit 0
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "fixture deploy $*"
EOF
chmod +x "$work/deploy.sh"

set +e
out_ok="$(run_doctor "$work")"
rc_ok=$?
set -e

if [ "$rc_ok" -eq 0 ]; then
    pass "complete fixture: exit 0"
else
    fail "complete fixture: expected exit 0, got $rc_ok — output: $out_ok"
fi
if echo "$out_ok" | grep -q "^FAIL"; then
    fail "complete fixture: unexpected FAIL lines — output: $out_ok"
else
    pass "complete fixture: no FAIL lines"
fi
if echo "$out_ok" | grep -q "^OK"; then
    pass "complete fixture: OK lines present"
else
    fail "complete fixture: no OK lines — output: $out_ok"
fi

# 6. logs/ 삭제 → FAIL ≥ 1, exit ≥ 1, [조치] 포함
rm -rf "$work/logs"

set +e
out_fail="$(run_doctor "$work")"
rc_fail=$?
set -e

fail_lines=$(echo "$out_fail" | grep -c "^FAIL" || true)
if [ "$rc_fail" -ge 1 ]; then
    pass "logs/ removed: exit >= 1 (got $rc_fail)"
else
    fail "logs/ removed: expected exit >= 1, got $rc_fail — output: $out_fail"
fi
if [ "$fail_lines" -ge 1 ]; then
    pass "logs/ removed: FAIL lines >= 1 (got $fail_lines)"
else
    fail "logs/ removed: no FAIL lines — output: $out_fail"
fi
if [ "$rc_fail" -eq "$fail_lines" ]; then
    pass "logs/ removed: exit code equals FAIL count"
else
    fail "logs/ removed: exit ($rc_fail) != FAIL count ($fail_lines)"
fi
if echo "$out_fail" | grep -q '\[조치\]'; then
    pass "logs/ removed: [조치] present"
else
    fail "logs/ removed: [조치] missing — output: $out_fail"
fi

# 7. --ping + PING_WRAPPER=fake → 크레딧 경고 + ping 결과 포함
mkdir -p "$work/logs"   # 픽스처 복원 (완전 상태로)

set +e
out_ping="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=ok run_doctor "$work" --ping)"
rc_ping=$?
set -e

if echo "$out_ping" | grep -q "크레딧"; then
    pass "--ping: credit warning printed"
else
    fail "--ping: credit warning missing — output: $out_ping"
fi
if echo "$out_ping" | grep -q "OK claudecli"; then
    pass "--ping: ping result included in output"
else
    fail "--ping: ping result missing — output: $out_ping"
fi
if [ "$rc_ping" -eq 0 ]; then
    pass "--ping: exit 0 on healthy fixture"
else
    fail "--ping: expected exit 0, got $rc_ping — output: $out_ping"
fi

# 8. 기본 실행(--ping 없음)은 ping을 하지 않는다
# 범위 주석: 아래 grep의 $out_ok는 TEST 5에서 캡처한 "완전한 픽스처" 실행 결과의
# 재사용이다. TEST 5는 deploy.sh + fake claudecli 셋업 후 doctor를 1회 돌려
# `OK claudecli`를 포함한 정상 출력을 캡처한다; TEST 8은 그 캡처값에 "ping 결과
# 라인(OK claudecli (<출력>) 등)"이 섞여 있지 않음을 검증한다. TEST 7이 $out_ping
# 별도 캡처를 갖는 것과 대조되는 구조.
if echo "$out_ok" | grep -q "OK claudecli ("; then
    fail "default run executed ping (found ping output without --ping)"
else
    pass "default run does not ping"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-20 acceptance checks passed."
    exit 0
else
    echo "One or more issue-20 acceptance checks failed."
    exit 1
fi
