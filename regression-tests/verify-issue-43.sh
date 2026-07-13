#!/usr/bin/env bash
# verify-issue-43.sh — 리뷰어 스코어보드 CLI 검증
# 픽스처 review-stats JSON으로 CLI를 실제 실행: 테이블 출력(리뷰어명·승격률),
# --json 유효성, 손상 JSON 내성(exit 0 + stderr 경고), stdlib-only,
# cheatsheet 사용법, 단위 테스트 통과를 단언한다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/tools/reviewer-scoreboard.py"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

[ -f "$CLI" ] && pass "CLI 존재" || fail "CLI 부재: $CLI"

# stdlib only — 서드파티 import 부재
if grep -E '^(import|from) ' "$CLI" | grep -vE '^(import|from) (argparse|json|sys|datetime|pathlib|__future__)' | grep -q .; then
    fail "표준 라이브러리 외 import 존재"
else
    pass "stdlib-only import"
fi

# 픽스처 구성
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/issues/archive/2026/07/01"
cat > "$T/repo/issues/issue-21__TYPE-agent-stats.json" <<'EOF'
{"issue": 21, "started": "2026-07-01T10:00:00", "reviewers": {"qwen": {"findings": 10, "gate_rejected": 4, "verify_rejected": 1, "must_fix": 2, "good_to_fix": 3}}, "derived_by_reviewers": [], "coders": {}}
EOF
cat > "$T/repo/issues/archive/2026/07/01/issue-20__TYPE-agent-stats.json" <<'EOF'
{"issue": 20, "started": "2026-07-01T09:00:00", "reviewers": {"minimax": {"findings": 4, "gate_rejected": 0, "verify_rejected": 0, "must_fix": 3, "good_to_fix": 1}}, "derived_by_reviewers": [], "coders": {}}
EOF
echo '{broken' > "$T/repo/issues/issue-9__TYPE-agent-stats.json"

# 테이블 출력 + 손상 내성
OUT="$(python3 "$CLI" "$T/repo" 2>"$T/err")"; RC=$?
[ $RC -eq 0 ] && pass "손상 JSON 포함 실행 exit 0" || fail "exit $RC"
echo "$OUT" | grep -q "qwen" && pass "테이블: qwen (라이브)" || fail "테이블에 qwen 없음"
echo "$OUT" | grep -q "minimax" && pass "테이블: minimax (아카이브)" || fail "테이블에 minimax 없음"
echo "$OUT" | grep -q "50.0%" && pass "테이블: qwen 승격률 50.0%" || fail "승격률 50.0% 없음"
echo "$OUT" | grep -q "교체 후보" && pass "해석 가이드 존재" || fail "해석 가이드 없음"
grep -q "issue-9" "$T/err" && pass "손상 JSON stderr 경고" || fail "손상 JSON 경고 없음"

# --json 유효성
python3 "$CLI" "$T/repo" --json 2>/dev/null | python3 -m json.tool >/dev/null 2>&1 \
    && pass "--json 유효한 JSON" || fail "--json 출력이 유효하지 않음"

# --since 필터
SINCE_CYCLES="$(python3 "$CLI" "$T/repo" --json --since 2026-07-02 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["cycles"])')"
[ "$SINCE_CYCLES" = "0" ] && pass "--since 필터 동작" || fail "--since 필터 오동작 (cycles=$SINCE_CYCLES)"

# cheatsheet 사용법
grep -q "reviewer-scoreboard" "$REPO_ROOT/cheatsheet.md" && pass "cheatsheet 사용법" || fail "cheatsheet에 사용법 없음"

# 단위 테스트 (이 이슈 전용 파일만 — tdd2 step 4 허용 범위)
if uv run --with pytest pytest -q "$REPO_ROOT/tests/test_reviewer_scoreboard.py" >/dev/null 2>&1; then
    pass "pytest 단위 테스트 통과"
else
    fail "pytest 단위 테스트 실패"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-43 acceptance checks passed."
    exit 0
else
    echo "One or more issue-43 acceptance checks failed."
    exit 1
fi
