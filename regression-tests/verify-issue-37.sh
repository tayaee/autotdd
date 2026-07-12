#!/usr/bin/env bash
# Verifies issue-37: spec 경로 규약 확정 — docs/spec-*.md → docs/spec/spec-*.md
# - README에 중첩형 docs/spec/spec-*.md가 2회 이상 존재
# - README에 플랫형 docs/spec-*.md 잔존 없음
# - verify-issue-36.sh가 갱신된 패턴으로 여전히 PASS
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO_ROOT/README.md"
V36="$REPO_ROOT/regression-tests/verify-issue-36.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. 중첩형 경로 2회 이상 -----
nested_count="$(grep -c 'docs/spec/spec-\*\.md' "$README" || true)"
if [ "$nested_count" -ge 2 ]; then
    pass "README: docs/spec/spec-*.md ${nested_count}회 존재"
else
    fail "README: docs/spec/spec-*.md 부족 (got: $nested_count, expected: >=2)"
fi

# ----- 2. 플랫형 잔존 없음 (docs/spec- 뒤에 바로 *가 오는 형태) -----
if grep -n 'docs/spec-\*' "$README" >/dev/null; then
    fail "README: 플랫형 docs/spec-*.md 잔존"
else
    pass "README: 플랫형 docs/spec-*.md 부재"
fi

# ----- 3. verify-issue-36.sh 여전히 PASS -----
if bash "$V36" >/tmp/verify-issue-37-v36.log 2>&1; then
    pass "verify-issue-36.sh 여전히 PASS"
else
    fail "verify-issue-36.sh 실패 — log: $(cat /tmp/verify-issue-37-v36.log)"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-37 acceptance checks passed."
    exit 0
else
    echo "One or more issue-37 acceptance checks failed."
    exit 1
fi
