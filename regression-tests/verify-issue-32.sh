#!/usr/bin/env bash
# Verifies issue-32: 트리거 스킬 SKILL.md ↔ 엔진 계약 정합화 (/autodev 동작 불능 수정)
# - 'autodev.py' 문자열이 .claude/skills/ 어디에도 없어야 함 (실존하지 않는 파일 호출 금지)
# - autodev/SKILL.md는 autofix.py를 --stream issue로 호출해야 함
# - autoqa/SKILL.md에는 doctor 전용 출력 토큰([원인]/[조치]/OK ) 지시가 없어야 함
#   (autoqa.py/error-to-autofix.py는 해당 토큰을 stdout에 출력하지 않음)
# - autofix/autodev SKILL.md는 autofix.py의 실측 stdout 계약(처리:.../FIXED=)을 반영
# - autoqafix/SKILL.md는 doctor 계약과 이미 일치하므로 불변
# - 구조적 잠금: 4개 SKILL.md가 참조하는 *.py 엔진 스크립트가 실제로 존재하는지 대조
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/.claude/skills"
ENGINE_DIR="$SKILLS_DIR/autoqafix"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. autodev.py 문자열이 스킬 트리에 전혀 없어야 함 -----
if grep -rn 'autodev\.py' "$SKILLS_DIR" >/dev/null 2>&1; then
    fail "'autodev.py' 문자열이 .claude/skills/에 남아있음: $(grep -rln 'autodev\.py' "$SKILLS_DIR" | tr '\n' ' ')"
else
    pass "autodev.py 문자열 부재"
fi

# ----- 2. autodev/SKILL.md에 autofix.py + --stream issue 등장 -----
AUTODEV_MD="$SKILLS_DIR/autodev/SKILL.md"
if grep -qF 'autofix.py' "$AUTODEV_MD" && grep -qF -- '--stream issue' "$AUTODEV_MD"; then
    pass "autodev/SKILL.md: autofix.py + --stream issue 등장"
else
    fail "autodev/SKILL.md에 autofix.py 또는 --stream issue 누락"
fi

# ----- 3. autoqa/SKILL.md에 doctor 전용 토큰 지시가 없어야 함 -----
AUTOQA_MD="$SKILLS_DIR/autoqa/SKILL.md"
if grep -qE '\[원인\]|\[조치\]|OK ' "$AUTOQA_MD"; then
    fail "autoqa/SKILL.md에 doctor 전용 토큰([원인]/[조치]/OK ) 지시가 남아있음"
else
    pass "autoqa/SKILL.md: doctor 전용 토큰 지시 없음"
fi

# ----- 4. autofix/autodev SKILL.md는 실측 stdout 계약(처리:.../FIXED=)을 반영해야 함 -----
for skill in autofix autodev; do
    path="$SKILLS_DIR/$skill/SKILL.md"
    if grep -qF '처리:' "$path" && grep -qF 'FIXED=' "$path"; then
        pass "$skill/SKILL.md: 처리:/FIXED= 실측 계약 반영"
    else
        fail "$skill/SKILL.md: 처리:/FIXED= 실측 계약 미반영"
    fi
done

# ----- 5. autoqafix/SKILL.md는 불변 (doctor 계약과 이미 일치) -----
AUTOQAFIX_MD="$SKILLS_DIR/autoqafix/SKILL.md"
if grep -qE '\[원인\]|\[조치\]' "$AUTOQAFIX_MD" && grep -qF 'FAIL ' "$AUTOQAFIX_MD" && grep -qF 'OK ' "$AUTOQAFIX_MD"; then
    pass "autoqafix/SKILL.md: doctor 계약 유지"
else
    fail "autoqafix/SKILL.md: doctor 계약 토큰 누락 (수정하면 안 됨)"
fi

# ----- 6. 구조적 잠금: 4개 SKILL.md가 참조하는 *.py 엔진 스크립트가 실존하는지 -----
for skill in autoqa autofix autodev autoqafix; do
    path="$SKILLS_DIR/$skill/SKILL.md"
    for py in $(grep -oE '[A-Za-z0-9_.-]+\.py' "$path" | sort -u); do
        if [ -f "$ENGINE_DIR/$py" ]; then
            pass "$skill/SKILL.md 참조 엔진 스크립트 실존: $py"
        else
            fail "$skill/SKILL.md가 참조하는 엔진 스크립트 없음: $py (expected at $ENGINE_DIR/$py)"
        fi
    done
done

if [ $FAIL -eq 0 ]; then
    echo "All issue-32 acceptance checks passed."
    exit 0
else
    echo "One or more issue-32 acceptance checks failed."
    exit 1
fi
