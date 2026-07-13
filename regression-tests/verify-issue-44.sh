#!/usr/bin/env bash
# verify-issue-44.sh — review-stats 스키마 보강 검증
# - SKILL.md Step 3-7: model 필드 명세 + unknown 폴백 + 리뷰 파일 첫 줄 참조
# - SKILL.md Step 3: 중복 finding → 전원 크레딧 규칙
# - tools/reviewer-scoreboard.py: model 필드가 든 stats JSON도 집계 불변
# - pytest: 위 계약을 단위 테스트로 고정
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"
CLI="$REPO_ROOT/tools/reviewer-scoreboard.py"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

has() {
    if grep -qF -e "$1" "$SKILL" 2>/dev/null; then
        pass "$2"
    else
        fail "누락: $2 (pattern: $1)"
    fi
}

# 1) SKILL.md — model 필드 규칙
has "model" "Step 3-7: reviewers 필수 필드에 model 명시"
has "unknown" "Step 3-7: model 미확보 시 unknown 폴백"
has "첫 줄" "Step 3-7: 리뷰 파일 첫 줄에서 모델명 추출"
has "버전 포함" "Step 3-7: 버전 포함 전사 명시"
has "침묵 금지" "Step 3-7: unknown 폴백 침묵 금지 명시"

# 2) SKILL.md — 중복 finding 전원 크레딧 규칙
has "전원" "Step 3: 전원 크레딧 명시"
has "중복" "Step 3: 중복 finding 케이스 명시"
has "1개만" "Step 3: 파생 이슈 1개만 생성"

# 3) scoreboard 무시 계약 — model 든/없는 픽스처로 동일 집계 단언
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo_with_model/issues"
mkdir -p "$T/repo_without_model/issues"

cat > "$T/repo_with_model/issues/issue-21__TYPE-review-stats.json" <<'EOF'
{"issue": 21, "date": "2026-07-01T10:00:00", "reviewers": {"qwen": {"model": "qwen 3 max preview", "findings": 10, "gate_rejected": 4, "verify_rejected": 1, "must_fix": 2, "good_to_fix": 3}}, "derived": []}
EOF
cat > "$T/repo_without_model/issues/issue-21__TYPE-review-stats.json" <<'EOF'
{"issue": 21, "date": "2026-07-01T10:00:00", "reviewers": {"qwen": {"findings": 10, "gate_rejected": 4, "verify_rejected": 1, "must_fix": 2, "good_to_fix": 3}}, "derived": []}
EOF

WITH_MODEL=$(python3 "$CLI" "$T/repo_with_model" --json 2>/dev/null)
WITHOUT_MODEL=$(python3 "$CLI" "$T/repo_without_model" --json 2>/dev/null)

if [ "$WITH_MODEL" = "$WITHOUT_MODEL" ]; then
    pass "model 필드 추가 시 집계(JSON) 불변"
else
    fail "model 필드 추가 시 집계 변경 — with=$WITH_MODEL without=$WITHOUT_MODEL"
fi

# 4) 테이블 출력에도 모델명이 노출되지 않아야 함 (집계 단위 = base명)
TABLE_OUT=$(python3 "$CLI" "$T/repo_with_model" 2>/dev/null)
echo "$TABLE_OUT" | grep -qi "qwen 3 max" \
    && fail "테이블에 model 버전명이 노출됨" \
    || pass "테이블 출력에 model 버전명 비노출"

# 5) 단위 테스트
if uv run --with pytest pytest -q "$REPO_ROOT/tests/test_reviewer_scoreboard.py" >/dev/null 2>&1; then
    pass "pytest 단위 테스트 통과 (model 필드 무시 계약 포함)"
else
    fail "pytest 단위 테스트 실패"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-44 acceptance checks passed."
    exit 0
else
    echo "One or more issue-44 acceptance checks failed."
    exit 1
fi