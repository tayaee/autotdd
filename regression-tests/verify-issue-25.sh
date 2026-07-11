#!/usr/bin/env bash
# Verifies issue-25: 빈 AUTOQAFIX_WRAPPERS — default 폴백 + WARN
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

# 픽스처 저장소 생성
fixture="$(bash "$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP+=("$fixture")
work="$fixture/work"

# deploy.sh 생성하여 doctor 통과 보장
cat > "$work/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy"
EOF
chmod +x "$work/deploy.sh"

run_doctor() {
    local dir="$1"; shift
    python3 "$DOCTOR_PY" --repo "$dir" "$@" 2>&1
}

# 1. AUTOQAFIX_WRAPPERS="" 일 때 기본 후보 3종 검사 수행 확인 (silent skip 없음)
# 픽스처 저장소에는 가짜 claudecli, minimaxcli, qwencli 가 wrappers/ 에 존재하거나 path 상에 있어야 함
# make-fixture-repo.sh는 claudecli, minimaxcli, qwencli에 대응되는 가짜 래퍼들을 wrappers 디렉토리에 넣어둠
# wrappers/ 디렉토리를 doctor가 보도록 AUTOQAFIX_WRAPPER_DIR를 강제함
export AUTOQAFIX_WRAPPER_DIR="$REPO_ROOT/regression-tests/lib" # 또는 픽스처의 wrappers 경로

# 실제 픽스처 저장소 내부의 wrappers 디렉토리를 참조
# make-fixture-repo.sh가 생성하는 픽스처에는 wrappers가 없거나, wrappers/ 폴더에 가짜 래퍼가 없을 수 있으므로
# wrappers 폴더를 만들고 3종 래퍼를 복사/생성해 둠
mkdir -p "$work/wrappers"
for w in claudecli minimaxcli qwencli; do
    cp "$LIB/fake-wrapper.sh" "$work/wrappers/${w}.sh"
    chmod +x "$work/wrappers/${w}.sh"
done
export AUTOQAFIX_WRAPPER_DIR="$work/wrappers"

# usage-*.py 스크립트들이 core.py와 같은 폴더(.claude/skills/autoqafix/)에 존재하므로,
# uv run으로 이들을 실행할 수 있음 (자체 3종 usage가 패키지에 들어있음)

set +e
out_empty="$(AUTOQAFIX_WRAPPERS="" run_doctor "$work")"
rc_empty=$?
set -e

if [ "$rc_empty" -eq 0 ]; then
    pass "AUTOQAFIX_WRAPPERS=\"\": exited 0"
else
    fail "AUTOQAFIX_WRAPPERS=\"\": expected exit 0, got $rc_empty — output: $out_empty"
fi

for w in claudecli minimaxcli qwencli; do
    if echo "$out_empty" | grep -q "OK 래퍼 $w"; then
        pass "AUTOQAFIX_WRAPPERS=\"\": checked wrapper $w successfully"
    else
        fail "AUTOQAFIX_WRAPPERS=\"\": failed to check wrapper $w — output: $out_empty"
    fi
done

# 2. AUTOQAFIX_WRAPPERS=":" 일 때 빈 spec이 되고, WARN 메시지 출력 + exit 미반영 확인
set +e
out_invalid="$(AUTOQAFIX_WRAPPERS=":" run_doctor "$work")"
rc_invalid=$?
set -e

if [ "$rc_invalid" -eq 0 ]; then
    pass "AUTOQAFIX_WRAPPERS=\":\": exited 0"
else
    fail "AUTOQAFIX_WRAPPERS=\":\": expected exit 0, got $rc_invalid — output: $out_invalid"
fi

if echo "$out_invalid" | grep -q "WARN — AUTOQAFIX_WRAPPERS가 비어있음, 래퍼 검사 생략"; then
    pass "AUTOQAFIX_WRAPPERS=\":\": WARN message printed"
else
    fail "AUTOQAFIX_WRAPPERS=\":\": WARN message missing — output: $out_invalid"
fi

# 래퍼 검사가 생략되었는지 확인 (OK 래퍼 claudecli 등의 출력어가 없어야 함)
if echo "$out_invalid" | grep -q "OK 래퍼"; then
    fail "AUTOQAFIX_WRAPPERS=\":\": wrappers checks were NOT skipped — output: $out_invalid"
else
    pass "AUTOQAFIX_WRAPPERS=\":\": wrapper checks skipped successfully"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-25 acceptance checks passed."
    exit 0
else
    echo "One or more issue-25 acceptance checks failed."
    exit 1
fi
