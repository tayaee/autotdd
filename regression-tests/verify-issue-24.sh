#!/usr/bin/env bash
# Verifies issue-24: lock 견고화
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

# 0. core --selftest 실행
if python3 "$SKILL_DIR/autoqafix_core.py" --selftest; then
    pass "core --selftest passed"
else
    fail "core --selftest failed"
fi

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

# 1. 잠금 파일 없음 (OK)
rm -rf "$work/.git/autoqafix.lock"
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK 뮤텍스 잠금 없음"; then
    pass "Scenario 1 (No Lock): OK"
else
    fail "Scenario 1 (No Lock): expected OK, got exit $rc, output: $out"
fi

# 2. 동일 호스트 alive (FAIL)
# 현재 쉘의 PID($$)를 사용하여 락 생성
cat > "$work/.git/autoqafix.lock" <<EOF
host=$(hostname)
pid=$$
role=qa
start=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL 뮤텍스 잠금" && echo "$out" | grep -q "이미 qa이 실행 중"; then
    pass "Scenario 2 (Same Host Alive): FAIL"
else
    fail "Scenario 2 (Same Host Alive): expected FAIL, got exit $rc, output: $out"
fi

# 3. 동일 호스트 dead (OK)
# 절대 살아있지 않을 법한 PID(예: 999999)로 생성
cat > "$work/.git/autoqafix.lock" <<EOF
host=$(hostname)
pid=999999
role=qa
start=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK 뮤텍스 잠금 없음 (stale lock — 소유 프로세스 사망"; then
    pass "Scenario 3 (Same Host Dead): OK"
else
    fail "Scenario 3 (Same Host Dead): expected OK, got exit $rc, output: $out"
fi

# 4. 다른 호스트 fresh (FAIL)
# 호스트는 다르고 4시간 이내의 시간
fresh_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$work/.git/autoqafix.lock" <<EOF
host=someotherhost
pid=1234
role=qa
start=$fresh_time
EOF
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL 뮤텍스 잠금" && echo "$out" | grep -q "이미 qa이 실행 중"; then
    pass "Scenario 4 (Other Host Fresh): FAIL"
else
    fail "Scenario 4 (Other Host Fresh): expected FAIL, got exit $rc, output: $out"
fi

# 5. 다른 호스트 stale (OK)
# 호스트는 다르고 4시간 이전의 시간
cat > "$work/.git/autoqafix.lock" <<EOF
host=someotherhost
pid=1234
role=qa
start=2020-01-01T00:00:00Z
EOF
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK 뮤텍스 잠금 없음 (stale lock — 보존 시간 만료"; then
    pass "Scenario 5 (Other Host Stale): OK"
else
    fail "Scenario 5 (Other Host Stale): expected OK, got exit $rc, output: $out"
fi

# 6. 비정상 pid (FAIL)
cat > "$work/.git/autoqafix.lock" <<EOF
host=$(hostname)
pid=abc
role=qa
start=2020-01-01T00:00:00Z
EOF
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL 뮤텍스 잠금" && echo "$out" | grep -q "잠금 파일이 비정상임" && echo "$out" | grep -q "\[조치\] .git/autoqafix.lock 삭제"; then
    pass "Scenario 6 (Abnormal PID): FAIL"
else
    fail "Scenario 6 (Abnormal PID): expected FAIL, got exit $rc, output: $out"
fi

# 7. 디렉터리 (FAIL)
rm -rf "$work/.git/autoqafix.lock"
mkdir -p "$work/.git/autoqafix.lock"
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL 뮤텍스 잠금" && echo "$out" | grep -q "잠금 파일이 비정상임" && echo "$out" | grep -q "\[조치\] .git/autoqafix.lock 삭제"; then
    pass "Scenario 7 (Directory Lock): FAIL"
else
    fail "Scenario 7 (Directory Lock): expected FAIL, got exit $rc, output: $out"
fi

# 8. 빈 파일 (FAIL)
rm -rf "$work/.git/autoqafix.lock"
touch "$work/.git/autoqafix.lock"
out="$(run_doctor "$work")"
rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL 뮤텍스 잠금" && echo "$out" | grep -q "잠금 파일이 비정상임" && echo "$out" | grep -q "\[조치\] .git/autoqafix.lock 삭제"; then
    pass "Scenario 8 (Empty Lock File): FAIL"
else
    fail "Scenario 8 (Empty Lock File): expected FAIL, got exit $rc, output: $out"
fi

# 9. acquire_lock이 비정상 잠금을 크래시 없이 회수하는지 테스트
# (1) 비정상 pid
cat > "$work/.git/autoqafix.lock" <<EOF
host=$(hostname)
pid=abc
role=qa
start=2020-01-01T00:00:00Z
EOF
if python3 -c "import sys; sys.path.insert(0, '$SKILL_DIR'); import autoqafix_core as core; sys.exit(0 if core.acquire_lock('fix', '$work') else 1)"; then
    pass "acquire_lock successfully reclaimed invalid PID lock"
else
    fail "acquire_lock failed to reclaim invalid PID lock"
fi

# (2) 디렉터리 잠금
rm -rf "$work/.git/autoqafix.lock"
mkdir -p "$work/.git/autoqafix.lock"
if python3 -c "import sys; sys.path.insert(0, '$SKILL_DIR'); import autoqafix_core as core; sys.exit(0 if core.acquire_lock('fix', '$work') else 1)"; then
    pass "acquire_lock successfully reclaimed directory lock"
else
    fail "acquire_lock failed to reclaim directory lock"
fi

# 10. doctor/autoqa/autofix에 _lock_path/_read_lock 호출이 없는지 소스코드 감사
if grep -rn --exclude-dir="__pycache__" "_lock_path" "$SKILL_DIR" | grep -v "autoqafix_core.py" | grep -v "git-029ce34.txt"; then
    fail "Found internal _lock_path usage in other files!"
else
    pass "No internal _lock_path usage outside autoqafix_core.py"
fi
if grep -rn --exclude-dir="__pycache__" "_read_lock" "$SKILL_DIR" | grep -v "autoqafix_core.py" | grep -v "git-029ce34.txt"; then
    fail "Found internal _read_lock usage in other files!"
else
    pass "No internal _read_lock usage outside autoqafix_core.py"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-24 acceptance checks passed."
    exit 0
else
    echo "One or more issue-24 acceptance checks failed."
    exit 1
fi
