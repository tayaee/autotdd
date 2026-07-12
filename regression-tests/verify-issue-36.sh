#!/usr/bin/env bash
# Verifies issue-36: mattpocock skills 1.1 개명 반영 — to-issues→to-tickets, to-prd→to-spec
# - 리포 스킬·README·CONTEXT·docs에 구 이름(to-issues/to-prd) 부재 (아카이브 제외)
# - autotddreview: to-tickets 사용
# - autotdd: 형제 스킬 예시에 to-tickets, to-spec 존재
# - README: docs/spec-*.md 규약 + /to-spec·/to-tickets 안내 존재
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOTDDREVIEW="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"
AUTOTDD="$REPO_ROOT/.claude/skills/autotdd/SKILL.md"
README="$REPO_ROOT/README.md"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. 구 이름 부재 (.claude/skills, README.md, CONTEXT.md, docs/) -----
old_names="$(grep -rn 'to-issues\|to-prd' \
    "$REPO_ROOT/.claude/skills/" "$README" "$REPO_ROOT/CONTEXT.md" "$REPO_ROOT/docs/" 2>/dev/null || true)"
if [ -z "$old_names" ]; then
    pass "구 이름(to-issues/to-prd) 참조 없음"
else
    fail "구 이름 참조 잔존: $old_names"
fi

# ----- 2. autotddreview: to-tickets 사용 -----
if grep -q 'to-tickets' "$AUTOTDDREVIEW"; then
    pass "autotddreview: to-tickets 사용"
else
    fail "autotddreview: to-tickets 미사용"
fi

# ----- 3. autotdd: to-tickets, to-spec 존재 -----
if grep -q 'to-tickets' "$AUTOTDD" && grep -q 'to-spec' "$AUTOTDD"; then
    pass "autotdd: to-tickets/to-spec 예시 반영"
else
    fail "autotdd: to-tickets/to-spec 예시 누락"
fi

# ----- 4. README: docs/spec/spec-*.md 규약 + 새 워크플로우 안내 -----
# (경로 형태는 issue-37에서 플랫형 docs/spec-*.md → 중첩형으로 확정)
if grep -q 'docs/spec/spec-\*\.md' "$README"; then
    pass "README: docs/spec/spec-*.md 규약 존재"
else
    fail "README: docs/spec/spec-*.md 규약 누락"
fi
if grep -q '/to-spec' "$README" && grep -q '/to-tickets' "$README"; then
    pass "README: /to-spec·/to-tickets 안내 존재"
else
    fail "README: /to-spec·/to-tickets 안내 누락"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-36 acceptance checks passed."
    exit 0
else
    echo "One or more issue-36 acceptance checks failed."
    exit 1
fi
