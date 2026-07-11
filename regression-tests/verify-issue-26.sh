#!/usr/bin/env bash
# Verifies issue-26: run_pings 크로스 플랫폼 — ping 3종 확장자 + OS별 인터프리터
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

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}
pass() {
    echo "PASS: $1"
}

# Windows 실동작은 CI 범위 밖임을 주석으로 명시 (run_with_timeout의 기존 관례와 동일)

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

# wrappers 디렉토리 셋업
mkdir -p "$work/wrappers"
export AUTOQAFIX_WRAPPER_DIR="$work/wrappers"
export AUTOQAFIX_WRAPPERS="claudecli:paid"

# 1. `.sh` ping 정상 경로 (Linux에서 기존 `--ping` 경로 회귀 없음)
# wrappers/ping-claudecli.sh 생성
cat > "$work/wrappers/ping-claudecli.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK claudecli ping"
exit 0
EOF
chmod +x "$work/wrappers/ping-claudecli.sh"

# claudecli.sh 도 만들어 둠 (doctor 통과용)
cp "$LIB/fake-wrapper.sh" "$work/wrappers/claudecli.sh"
chmod +x "$work/wrappers/claudecli.sh"

set +e
out_sh="$(run_doctor "$work" --ping)"
rc_sh=$?
set -e

if [ "$rc_sh" -eq 0 ] && echo "$out_sh" | grep -q "OK claudecli ping"; then
    pass "Scenario 1 (.sh ping normal path): OK"
else
    fail "Scenario 1 (.sh ping normal path): expected OK, got exit $rc_sh, output: $out_sh"
fi

# 2. `.sh` 제거 + `.bat`만 존재 시 크래시 없이 정의된 동작 (FAIL 또는 실행)
# Linux 환경이므로 cmd /c ping-claudecli.bat 실행 시 FileNotFoundError가 날 것임.
# 크래시(traceback)가 없고, FAIL ping-claudecli가 정상 출력되어야 함.
rm -f "$work/wrappers/ping-claudecli.sh"
cat > "$work/wrappers/ping-claudecli.bat" <<'EOF'
echo "OK bat ping"
EOF

set +e
out_bat="$(run_doctor "$work" --ping)"
rc_bat=$?
set -e

# traceback이 없고 FAIL ping-claudecli가 있는지 확인
if echo "$out_bat" | grep -q "Traceback"; then
    fail "Scenario 2 (.bat only): crashed with traceback — output: $out_bat"
elif [ "$rc_bat" -ge 1 ] && echo "$out_bat" | grep -q "FAIL ping-claudecli" && echo "$out_bat" | grep -q "실행 실패"; then
    pass "Scenario 2 (.bat only): correctly failed without crash on Linux"
else
    fail "Scenario 2 (.bat only): expected FAIL, got exit $rc_bat, output: $out_bat"
fi

# 3. ping 파일이 전혀 없으면 기존대로 FAIL ping-<name> (경로 표기)
rm -f "$work/wrappers/ping-claudecli.bat"

# default wrappers 디렉토리에조차 없는 임의의 래퍼 nonexistentcli 사용
export AUTOQAFIX_WRAPPERS="nonexistentcli:paid"

# doctor 통과를 위해 nonexistentcli.sh 셋업
cp "$LIB/fake-wrapper.sh" "$work/wrappers/nonexistentcli.sh"
chmod +x "$work/wrappers/nonexistentcli.sh"

# SCRIPT_DIR에 usage-nonexistentcli.py 셋업 및 cleanup 등록
cp "$SKILL_DIR/usage-claudecli.py" "$SKILL_DIR/usage-nonexistentcli.py"
CLEANUP_FILES+=("$SKILL_DIR/usage-nonexistentcli.py")

set +e
out_none="$(run_doctor "$work" --ping)"
rc_none=$?
set -e

expected_missing_path="$SKILL_DIR/wrappers/ping-nonexistentcli.sh" # POSIX 이므로 기본 확장자인 .sh 가 표기됨
if [ "$rc_none" -ge 1 ] && echo "$out_none" | grep -q "FAIL ping-nonexistentcli" && echo "$out_none" | grep -q "$expected_missing_path 없음"; then
    pass "Scenario 3 (No ping file): correctly reported missing path"
else
    fail "Scenario 3 (No ping file): expected FAIL with path, got exit $rc_none, output: $out_none"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-26 acceptance checks passed."
    exit 0
else
    echo "One or more issue-26 acceptance checks failed."
    exit 1
fi
