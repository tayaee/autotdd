#!/usr/bin/env bash
# Verifies issue-21: Claude Code 트리거 스킬 4종 + install.sh
# - .claude/skills/{autoqa,autofix,autodev,autoqafix}/SKILL.md 4종이 존재하고
#   frontmatter(`---`로 열고 닫기, name/description 포함)가 유효하다.
# - 각 SKILL.md 본문은 자기 자신의 트리거(`/autoqa` 등) + smarthome 충돌 방지 +
#   issue/코드 직접 수정 금지 문구를 포함한다.
# - repo 루트의 install.sh는 4개 폴더를 ~/.claude/skills/로 symlink하며 idempotent이다.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

# 실 HOME(가짜 HOME이 아닌, 이 스크립트를 실행하는 호스트의 진짜 HOME) —
# 아래 fake-HOME 설치 실험이 여기를 건드리지 않는지 스냅샷 비교로 검증한다.
REAL_HOME_SKILLS="$HOME/.claude/skills"

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

# ----- 1. SKILL.md 4종 frontmatter + 본문 계약 -----
for skill in autoqa autofix autodev autoqafix; do
    path="$REPO_ROOT/.claude/skills/$skill/SKILL.md"
    if [ ! -f "$path" ]; then
        fail "$path 없음"
        continue
    fi
    # 첫 줄과 둘째 닫는 --- 확인
    first_line="$(sed -n '1p' "$path")"
    if [ "$first_line" != "---" ]; then
        fail "$path: 첫 줄이 '---'가 아님 (got: $first_line)"
        continue
    fi
    closing_line="$(grep -n '^---$' "$path" | sed -n '2p' | cut -d: -f1)"
    if [ -z "$closing_line" ]; then
        fail "$path: 닫는 '---' 없음 (frontmatter 미종결)"
        continue
    fi
    # name 필드 존재
    if ! grep -q '^name:' "$path"; then
        fail "$path: 'name:' 필드 없음"
    else
        # name 값이 스킬 이름과 일치
        name_val="$(grep -E '^name:' "$path" | head -1 | sed -E 's/^name:[[:space:]]*//')"
        if [ "$name_val" != "$skill" ]; then
            fail "$path: name 값이 '$skill'과 불일치 (got: $name_val)"
        fi
    fi
    # description 필드 존재
    if ! grep -q '^description:' "$path"; then
        fail "$path: 'description:' 필드 없음"
    fi
    # 본문 트리거 문구 (/autoqa 등)
    trigger="/$skill"
    if ! grep -q -F "$trigger" "$path"; then
        fail "$path: 본문에 트리거 문구 '$trigger' 없음"
    fi
    # smarthome 충돌 방지 문구
    if ! grep -q -F "smarthome" "$path"; then
        fail "$path: 'smarthome' 충돌 방지 문구 없음"
    fi
    # 스킬 자신의 issue/코드 작성·수정 금지 문구
    if ! grep -qE '금지|하지 말|쓰지 말|고치지 말|하지마' "$path"; then
        fail "$path: '이 스킬은 issue 본문 작성/코드 수정 금지' 문구 없음"
    fi
    pass "$skill/SKILL.md frontmatter + 본문 계약 OK"
done

# ----- 2. install.sh 존재 + 실행 권한 -----
if [ ! -f "$INSTALL_SH" ]; then
    fail "$INSTALL_SH 없음"
else
    if [ ! -x "$INSTALL_SH" ]; then
        fail "$INSTALL_SH 실행 권한 없음"
    else
        pass "install.sh 존재 + 실행 가능"
    fi
fi

# ----- 3. install.sh idempotent + symlink 검증 (가짜 HOME) -----
if [ -f "$INSTALL_SH" ] && [ -x "$INSTALL_SH" ]; then
    fake_home="$(mktemp -d)"
    CLEANUP+=("$fake_home")
    mkdir -p "$fake_home/.claude/skills"

    # 실 HOME 오염 방지 스냅샷 — fake-HOME 설치 실험 전, 대상 4개 항목의
    # 상태(부재/inode+mtime)를 기록해 뒀다가 실험 후 동일한지 assert한다.
    declare -A real_snapshot
    for skill in autoqa autofix autodev autoqafix; do
        p="$REAL_HOME_SKILLS/$skill"
        if [ -e "$p" ] || [ -L "$p" ]; then
            real_snapshot["$skill"]="$(stat -c '%i:%Y' "$p" 2>/dev/null || echo "?")"
        else
            real_snapshot["$skill"]="ABSENT"
        fi
    done

    # 1차 실행 — exit code를 그 자리에서 rc1으로 캡처 (재실행으로 다시 얻지 않음)
    rc1=0
    HOME="$fake_home" bash "$INSTALL_SH" > "$fake_home/run1.log" 2>&1 || rc1=$?
    if [ "$rc1" -eq 0 ]; then
        pass "install.sh 1차 실행 성공"
    else
        fail "install.sh 1차 실행 실패 — log: $(cat "$fake_home/run1.log")"
    fi
    # 1차에서 4개 symlink가 만들어졌는지
    for skill in autoqa autofix autodev autoqafix; do
        link="$fake_home/.claude/skills/$skill"
        if [ ! -L "$link" ]; then
            fail "1차 실행 후 symlink 없음: $link"
        fi
    done

    # 2차 실행 (idempotent) — exit code를 그 자리에서 rc2로 캡처
    rc2=0
    HOME="$fake_home" bash "$INSTALL_SH" > "$fake_home/run2.log" 2>&1 || rc2=$?
    if [ "$rc2" -eq 0 ]; then
        pass "install.sh 2차 실행 성공 (idempotent)"
    else
        fail "install.sh 2차 실행 실패 (idempotent 위반) — log: $(cat "$fake_home/run2.log")"
    fi
    # 1차/2차 exit code 동일 검사 — rc1/rc2는 위에서 이미 캡처됐으므로 재실행 불필요
    if [ "$rc1" = "$rc2" ]; then
        pass "install.sh 1차/2차 exit code 동일 ($rc1)"
    else
        fail "install.sh 1차/2차 exit code 불일치 ($rc1 vs $rc2)"
    fi
    # 2차 실행에 skip 신호 메시지
    if grep -qE '이미|exists|skip|건너뜀|already' "$fake_home/run2.log"; then
        pass "install.sh 2차 실행에 skip 신호 메시지 존재"
    else
        fail "install.sh 2차 실행에 skip 신호 메시지 없음 — log: $(cat "$fake_home/run2.log")"
    fi

    # 4개 symlink가 모두 repo 폴더를 가리키는지
    for skill in autoqa autofix autodev autoqafix; do
        link="$fake_home/.claude/skills/$skill"
        if [ -L "$link" ]; then
            target="$(readlink "$link")"
            resolved="$(readlink -f "$link")"
            expected="$REPO_ROOT/.claude/skills/$skill"
            if [ "$resolved" = "$expected" ]; then
                pass "symlink $skill → $expected"
            else
                fail "symlink $skill 잘못된 대상: link=$target resolved=$resolved expected=$expected"
            fi
        else
            fail "$skill symlink 부재 (2차 후)"
        fi
    done

    # 실 HOME 오염 검증 — 설치 전 스냅샷과 설치 후 상태를 비교해 실제로
    # 아무것도 바뀌지 않았음을 assert한다 (예전엔 ':' no-op만 실행하는
    # 빈 껍데기였음 — issue-34).
    for skill in autoqa autofix autodev autoqafix; do
        p="$REAL_HOME_SKILLS/$skill"
        if [ -e "$p" ] || [ -L "$p" ]; then
            after="$(stat -c '%i:%Y' "$p" 2>/dev/null || echo "?")"
        else
            after="ABSENT"
        fi
        if [ "$after" = "${real_snapshot[$skill]}" ]; then
            pass "실 HOME 오염 없음: $skill 상태 불변 (${real_snapshot[$skill]})"
        else
            fail "실 HOME 오염 발생: $skill 상태 변경 (before=${real_snapshot[$skill]} after=$after)"
        fi
    done
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-21 acceptance checks passed."
    exit 0
else
    echo "One or more issue-21 acceptance checks failed."
    exit 1
fi