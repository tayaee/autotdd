#!/usr/bin/env bash
# verify-issue-46.sh — coding-stats.json 통합 (MVP + Review 결함 수집 및 집계)
# 주의: issue-47에서 coding-stats.json은 agent-stats.json으로 재통합됨 — 이 스크립트의
# 픽스처 파일명·SKILL.md 단언은 그에 맞춰 갱신됨(regression-tests/verify-issue-46.conflict-with-47.md 참조).
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_REVIEW="$REPO_ROOT/.claude/skills/autotddreviewfix/SKILL.md"
SKILL_TDD2="$REPO_ROOT/.claude/skills/tdd2/SKILL.md"
GLOBAL_SKILL_REVIEW="$HOME/.claude/skills/autotddreviewfix/SKILL.md"
GLOBAL_SKILL_TDD2="$HOME/.claude/skills/tdd2/SKILL.md"
SPEC="$REPO_ROOT/docs/spec/spec-issue-filenames.md"
CLI="$REPO_ROOT/tools/reviewer-scoreboard.py"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

has() {
    local file="$1" pattern="$2" desc="$3"
    if grep -qF -e "$pattern" "$file" 2>/dev/null; then
        pass "$desc"
    else
        fail "누락: $desc (file=$file pattern=$pattern)"
    fi
}

not_has() {
    local file="$1" pattern="$2" desc="$3"
    if grep -qF -e "$pattern" "$file" 2>/dev/null; then
        fail "존재하면 안 됨: $desc (file=$file pattern=$pattern)"
    else
        pass "$desc"
    fi
}

# 1) SKILL.md 정적 검사 (log-run 문자열 0건)
for f in "$SKILL_REVIEW" "$SKILL_TDD2" "$GLOBAL_SKILL_REVIEW" "$GLOBAL_SKILL_TDD2"; do
    not_has "$f" "log-run" "SKILL.md log-run 언급 제거: $(basename "$f")"
    not_has "$f" "coder-stats.jsonl" "SKILL.md coder-stats.jsonl 언급 제거: $(basename "$f")"
done

# agent-stats.json 스키마 필드명 존재 단언 (issue-47: coding-stats.json에서 이관)
has "$SKILL_TDD2" "agent-stats.json" "tdd2: agent-stats.json 언급"
has "$SKILL_TDD2" "static_analysis_failures" "tdd2: static_analysis_failures 스키마 포함"
has "$SKILL_REVIEW" "agent-stats.json" "autotddreviewfix: agent-stats.json 언급"
has "$SKILL_REVIEW" "review_outcome" "autotddreviewfix: review_outcome 스키마 포함"
has "$SKILL_REVIEW" "refix_plans_written" "autotddreviewfix: refix_plans_written 스키마 포함"

# 2) spec-issue-filenames.md에 coder-stats/coding-stats 잔존 0건, agent-stats 존재 단언
not_has "$SPEC" "coder-stats" "spec: coder-stats 제거"
not_has "$SPEC" "coding-stats" "spec: coding-stats 제거 (issue-47)"
has "$SPEC" "agent-stats" "spec: agent-stats 추가"

# 3) 픽스처 agent-stats.json으로 스코어보드 실행
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/issues"

# 픽스처 1: 정적분석만 있는 것 (loc=100, ruff=2, pyright=1)
cat > "$T/repo/issues/issue-10__TYPE-agent-stats.json" <<'EOF'
{
  "issue": 10,
  "coders": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "mvp": {
        "ts": "2026-07-13T01:00:00Z",
        "loc_added": 100,
        "static_analysis_failures": { "ruff": 2, "pyright": 1 }
      }
    }
  }
}
EOF

# 픽스처 2: review_outcome까지 병합된 것 (loc=200, ruff=0, pyright=0, must_fix=2, good=3, refix=1)
cat > "$T/repo/issues/issue-20__TYPE-agent-stats.json" <<'EOF'
{
  "issue": 20,
  "coders": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "mvp": {
        "ts": "2026-07-13T02:00:00Z",
        "loc_added": 200,
        "static_analysis_failures": { "ruff": 0, "pyright": 0 }
      },
      "review_outcome": {
        "ts": "2026-07-13T03:00:00Z",
        "findings_received": 5,
        "must_fix_count": 2,
        "good_to_fix_count": 3,
        "refix_plans_written": 1
      }
    }
  }
}
EOF

# 픽스처 3: static_analysis_failures가 null인 것 (loc=50, ruff=null, pyright=null)
cat > "$T/repo/issues/issue-30__TYPE-agent-stats.json" <<'EOF'
{
  "issue": 30,
  "coders": {
    "qwen": {
      "model": "Qwen 2.5",
      "mvp": {
        "ts": "2026-07-13T04:00:00Z",
        "loc_added": 50,
        "static_analysis_failures": { "ruff": null, "pyright": null }
      }
    }
  }
}
EOF

# 스코어보드 실행
JSON_OUT=$(python3 "$CLI" "$T/repo" --json 2>/dev/null)
echo "$JSON_OUT" | python3 -m json.tool >/dev/null 2>&1 && pass "scoreboard: JSON 출력 유효" || fail "scoreboard: JSON 출력 무효"

# sonnet5: loc=300, static_failures=3, must_fix=2
# Total density = (3+2)/300*1000 = 16.7
# Static component = 3/300*1000 = 10.0
# Review component = 2/300*1000 = 6.7
DENSITY=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["sonnet5"]["defect_density_per_kloc"])')
STATIC_D=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["sonnet5"]["static_density_per_kloc"])')
REVIEW_D=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["sonnet5"]["review_density_per_kloc"])')

[ "$DENSITY" = "16.7" ] && pass "scoreboard: defect 밀도 16.7/kloc" || fail "scoreboard: density=$DENSITY (expected 16.7)"
[ "$STATIC_D" = "10.0" ] && pass "scoreboard: static 밀도 10.0/kloc" || fail "scoreboard: static_density=$STATIC_D (expected 10.0)"
[ "$REVIEW_D" = "6.7" ] && pass "scoreboard: review 밀도 6.7/kloc" || fail "scoreboard: review_density=$REVIEW_D (expected 6.7)"

# qwen: loc=50, static_failures=0, must_fix=0 -> density=0.0
QWEN_D=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["qwen"]["defect_density_per_kloc"])')
[ "$QWEN_D" = "0.0" ] && pass "scoreboard: qwen defect 밀도 0.0/kloc" || fail "scoreboard: qwen density=$QWEN_D (expected 0.0)"

# 테이블 형태 확인
TABLE_OUT=$(python3 "$CLI" "$T/repo" 2>/dev/null)
echo "$TABLE_OUT" | grep -q "=== coder 섹션 ===" && pass "scoreboard: coder 섹션 헤더 존재" || fail "scoreboard: coder 섹션 헤더 없음"
echo "$TABLE_OUT" | grep -q "sonnet5" && pass "scoreboard: sonnet5 행 출력 확인" || fail "scoreboard: sonnet5 행 출력 없음"

# 4) pytest 단위 테스트
if uv run --with pytest pytest -q "$REPO_ROOT/tests/test_reviewer_scoreboard_coder.py" >/dev/null 2>&1; then
    pass "pytest 게이트 통과"
else
    fail "pytest 게이트 실패"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-46 acceptance checks passed."
    exit 0
else
    echo "One or more issue-46 acceptance checks failed."
    exit 1
fi
