#!/usr/bin/env bash
# Verifies issue-34: verify-issue-21.sh 정리 — 빈 no-op 검사 해소 + 중복 실행 제거
# - install.sh 호출은 1·2차 실행 2회만 남아야 함 (3·4차 재실행 제거)
# - '${HOME:-$HOME}' 같은 무의미 기본값 표현이 사라져야 함
# - no-op(':'만 있는) 검증 루프가 없어야 함
# - verify-issue-21.sh 자체가 여전히 PASS해야 함
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V21="$REPO_ROOT/regression-tests/verify-issue-21.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 1. install.sh 호출 횟수 = 2 (1·2차만 남음) -----
call_count="$(grep -c 'bash "$INSTALL_SH"' "$V21" || true)"
if [ "$call_count" = "2" ]; then
    pass "install.sh 호출 횟수 = 2 (1·2차 실행만)"
else
    fail "install.sh 호출 횟수 불일치 (got: $call_count, expected: 2)"
fi

# ----- 2. '${HOME:-$HOME}' 부재 -----
if grep -n ':-\$HOME' "$V21" >/dev/null; then
    fail "'\${HOME:-\$HOME}' 표현이 여전히 존재함"
else
    pass "'\${HOME:-\$HOME}' 표현 부재"
fi

# ----- 3. no-op(':'만 있는) 검증 루프 부재 -----
# 루프 본문이 콜론 한 줄(":")만인 for/if 블록을 찾는다.
if awk '
    /^\s*:\s*$/ { print NR }
' "$V21" | grep -q .; then
    fail "no-op ':' 단독 라인이 여전히 존재함"
else
    pass "no-op ':' 단독 라인 없음"
fi

# ----- 4. verify-issue-21.sh 자체가 여전히 PASS -----
if bash "$V21" >/tmp/verify-issue-34-v21.log 2>&1; then
    pass "verify-issue-21.sh 여전히 PASS"
else
    fail "verify-issue-21.sh 실패 — log: $(cat /tmp/verify-issue-34-v21.log)"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-34 acceptance checks passed."
    exit 0
else
    echo "One or more issue-34 acceptance checks failed."
    exit 1
fi
