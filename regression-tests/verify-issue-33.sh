#!/usr/bin/env bash
# Verifies issue-33: install.sh 견고화 — dangling symlink 감지·재연결 + set -e
# - 깨진(대상이 사라진) symlink가 있으면 자동으로 올바른 $src로 재연결한다
# - 일반 파일/디렉토리는 절대 삭제/덮어쓰지 않는다 (기존 WARN + 건너뜀 유지)
# - set -euo pipefail로 전환되어 있다
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

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

# ----- 0. set -euo pipefail 전환 확인 -----
if grep -n 'set -euo pipefail' "$INSTALL_SH" >/dev/null; then
    pass "install.sh: set -euo pipefail 존재"
else
    fail "install.sh: set -euo pipefail 없음"
fi

# ----- 1. 정상 설치 후 링크 4개를 존재하지 않는 경로로 바꿔치기 -> 재실행 -> 재연결 -----
fake_home="$(mktemp -d)"
CLEANUP+=("$fake_home")
mkdir -p "$fake_home/.claude/skills"

if HOME="$fake_home" bash "$INSTALL_SH" > "$fake_home/run1.log" 2>&1; then
    pass "1차 설치 성공"
else
    fail "1차 설치 실패 — $(cat "$fake_home/run1.log")"
fi

for skill in autoqa autofix autodev autoqafix; do
    link="$fake_home/.claude/skills/$skill"
    rm -f "$link"
    ln -s "$fake_home/.claude/skills/__nonexistent_${skill}__" "$link"
done

if HOME="$fake_home" bash "$INSTALL_SH" > "$fake_home/run_reconnect.log" 2>&1; then
    pass "깨진 symlink 상태에서 install.sh 재실행 성공 (exit 0)"
else
    fail "깨진 symlink 상태에서 install.sh 재실행 실패 — $(cat "$fake_home/run_reconnect.log")"
fi

for skill in autoqa autofix autodev autoqafix; do
    link="$fake_home/.claude/skills/$skill"
    expected="$REPO_ROOT/.claude/skills/$skill"
    if [ -L "$link" ]; then
        target="$(readlink -f "$link")"
        if [ "$target" = "$expected" ]; then
            pass "$skill: 깨진 링크가 올바른 \$src로 재연결됨"
        else
            fail "$skill: 재연결 후 대상이 예상과 다름 (got: $target expected: $expected)"
        fi
    else
        fail "$skill: 재연결 후 symlink가 아님"
    fi
done

if grep -q '재연결' "$fake_home/run_reconnect.log"; then
    pass "재연결(깨진 링크 복구) 메시지 출력 확인"
else
    fail "재연결 메시지 없음 — log: $(cat "$fake_home/run_reconnect.log")"
fi

# ----- 2. 재연결 직후 재실행 -> idempotent (이미 설치됨 4건, 상태 변화 없음) -----
before_targets=()
for skill in autoqa autofix autodev autoqafix; do
    before_targets+=("$(readlink -f "$fake_home/.claude/skills/$skill")")
done

if HOME="$fake_home" bash "$INSTALL_SH" > "$fake_home/run_idempotent.log" 2>&1; then
    pass "재연결 후 재실행 성공"
else
    fail "재연결 후 재실행 실패"
fi

already_count="$(grep -c '^이미 설치됨' "$fake_home/run_idempotent.log" || true)"
if [ "$already_count" = "4" ]; then
    pass "재연결 후 재실행: 이미 설치됨 4건"
else
    fail "재연결 후 재실행: 이미 설치됨 건수 불일치 (got: $already_count)"
fi

i=0
state_changed=0
for skill in autoqa autofix autodev autoqafix; do
    after="$(readlink -f "$fake_home/.claude/skills/$skill")"
    if [ "$after" != "${before_targets[$i]}" ]; then
        state_changed=1
    fi
    i=$((i + 1))
done
if [ "$state_changed" -eq 0 ]; then
    pass "재연결 후 재실행: 상태 변화 없음"
else
    fail "재연결 후 재실행: symlink 대상이 변경됨"
fi

# ----- 3. symlink가 아닌 파일/디렉토리 충돌 -> 기존대로 WARN + 건너뜀 (삭제 금지) -----
fake_home2="$(mktemp -d)"
CLEANUP+=("$fake_home2")
mkdir -p "$fake_home2/.claude/skills/autoqa"
echo "sentinel" > "$fake_home2/.claude/skills/autoqa/marker.txt"

conflict_rc=0
HOME="$fake_home2" bash "$INSTALL_SH" > "$fake_home2/run_conflict.log" 2>&1 || conflict_rc=$?

if [ "$conflict_rc" -ne 0 ]; then
    pass "일반 디렉토리 충돌 시 install.sh nonzero exit (missing>0)"
else
    fail "일반 디렉토리 충돌 시에도 exit 0 — WARN 미반영 가능성"
fi

if [ -f "$fake_home2/.claude/skills/autoqa/marker.txt" ]; then
    pass "일반 디렉토리 충돌: 기존 파일 보존됨 (삭제되지 않음)"
else
    fail "일반 디렉토리 충돌: 기존 파일이 사라짐 — 삭제 금지 위반"
fi

if grep -q 'WARN' "$fake_home2/run_conflict.log"; then
    pass "일반 디렉토리 충돌: WARN 메시지 출력"
else
    fail "일반 디렉토리 충돌: WARN 메시지 없음"
fi

# ----- 4. 연속 2회 실행 exit 0 동일 -----
fake_home3="$(mktemp -d)"
CLEANUP+=("$fake_home3")
mkdir -p "$fake_home3/.claude/skills"
rc1=0
HOME="$fake_home3" bash "$INSTALL_SH" >/dev/null 2>&1 || rc1=$?
rc2=0
HOME="$fake_home3" bash "$INSTALL_SH" >/dev/null 2>&1 || rc2=$?
if [ "$rc1" = "$rc2" ]; then
    pass "연속 2회 실행 exit code 동일 ($rc1)"
else
    fail "연속 2회 실행 exit code 불일치 ($rc1 vs $rc2)"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-33 acceptance checks passed."
    exit 0
else
    echo "One or more issue-33 acceptance checks failed."
    exit 1
fi
