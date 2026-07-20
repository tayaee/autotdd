#!/usr/bin/env bash
# verify-issue-47.sh — agent-stats.json 통합 (review-stats.json + coding-stats.json),
# started/archived/duration 도입, derived → derived_by_reviewers 검증.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/docs/spec/spec-issue-filenames.md"
SKILL_TDD2="$REPO_ROOT/.claude/skills/tdd2/SKILL.md"
SKILL_REVIEW="$REPO_ROOT/.claude/skills/autotddreviewfix/SKILL.md"
GLOBAL_SKILL_TDD2="$HOME/.claude/skills/tdd2/SKILL.md"
GLOBAL_SKILL_REVIEW="$HOME/.claude/skills/autotddreviewfix/SKILL.md"
ARCHIVE_HELPER="$REPO_ROOT/.claude/skills/aacpd/defaults/agent-stats-archive.py"
CLI="$REPO_ROOT/tools/reviewer-scoreboard.py"
AACP="$REPO_ROOT/.claude/skills/aacpd/aacp.sh"

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

# ----- 1. spec-issue-filenames.md -----
has "$SPEC" "agent-stats" "spec: agent-stats 존재"
not_has "$SPEC" "review-stats" "spec: review-stats 완전 제거"
not_has "$SPEC" "coding-stats" "spec: coding-stats 완전 제거"

# ----- 2. tdd2/autotddreviewfix SKILL.md (로컬+전역) -----
for f in "$SKILL_TDD2" "$SKILL_REVIEW" "$GLOBAL_SKILL_TDD2" "$GLOBAL_SKILL_REVIEW"; do
    not_has "$f" "review-stats.json" "SKILL.md 구 review-stats.json 언급 0건: $(basename "$(dirname "$f")")"
    not_has "$f" "coding-stats.json" "SKILL.md 구 coding-stats.json 언급 0건: $(basename "$(dirname "$f")")"
    has "$f" "agent-stats.json" "SKILL.md agent-stats.json 언급: $(basename "$(dirname "$f")")"
done
has "$SKILL_TDD2" "started" "tdd2: started 타임스탬프 기록 서술"
has "$SKILL_REVIEW" "derived_by_reviewers" "autotddreviewfix: derived_by_reviewers 필드명"

# ----- 3. 신규 헬퍼: archived/duration 계산 -----
[ -f "$ARCHIVE_HELPER" ] && pass "헬퍼 존재: agent-stats-archive.py" || fail "헬퍼 부재: $ARCHIVE_HELPER"

if grep -E '^(import|from) ' "$ARCHIVE_HELPER" | grep -vE '^(import|from) (json|re|sys|datetime|pathlib|__future__)' | grep -q .; then
    fail "agent-stats-archive.py: 표준 라이브러리 외 import 존재"
else
    pass "agent-stats-archive.py: stdlib-only import"
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/issues"

STARTED="$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
cat > "$T/repo/issues/issue-90__TYPE-agent-stats.json" <<EOF
{"issue": 90, "started": "$STARTED", "coders": {"sonnet5": {"model": "Claude Sonnet 5"}}}
EOF

uv run "$ARCHIVE_HELPER" "$T/repo" issue-90 >/tmp/verify47-archive.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "archive 헬퍼: 정상 파일 exit 0" || fail "archive 헬퍼 exit $RC: $(cat /tmp/verify47-archive.out)"

python3 - "$T/repo/issues/issue-90__TYPE-agent-stats.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert "archived" in data, "archived 필드 없음"
assert data["duration"].startswith("PT2H"), f"duration={data['duration']!r} (2시간 기대)"
assert data["issue"] == 90 and data["coders"]["sonnet5"]["model"] == "Claude Sonnet 5", "기존 필드 보존 실패"
print("OK")
PYEOF
[ $? -eq 0 ] && pass "archive 헬퍼: archived/duration 정확히 채움, 기존 필드 보존" || fail "archive 헬퍼: 필드 검증 실패"

# started 없는 픽스처는 에러 종료
cat > "$T/repo/issues/issue-91__TYPE-agent-stats.json" <<'EOF'
{"issue": 91, "coders": {}}
EOF
uv run "$ARCHIVE_HELPER" "$T/repo" issue-91 >/tmp/verify47-archive-err.out 2>&1
RC=$?
[ $RC -ne 0 ] && pass "archive 헬퍼: started 없으면 에러 종료" || fail "archive 헬퍼: started 없어도 exit 0"
grep -qi "started" /tmp/verify47-archive-err.out && pass "archive 헬퍼: started 누락 stderr 안내" || fail "archive 헬퍼: started 누락 안내 없음"

# ----- 4. reviewer-scoreboard.py — agent-stats.json 통합 집계 -----
mkdir -p "$T/repo2/issues"
cat > "$T/repo2/issues/issue-92__TYPE-agent-stats.json" <<'EOF'
{
  "issue": 92,
  "started": "2026-07-01T10:00:00Z",
  "archived": "2026-07-02T12:00:00Z",
  "duration": "P1DT2H",
  "reviewers": {"qwen": {"model": "Qwen 3", "findings": 4, "gate_rejected": 0, "verify_rejected": 0, "must_fix": 2, "good_to_fix": 2}},
  "derived_by_reviewers": ["issue-93-fixing-92.md"],
  "coders": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "mvp": {"ts": "2026-07-01T11:00:00Z", "loc_added": 100, "static_analysis_failures": {"ruff": 1, "pyright": 0}},
      "review_outcome": {"ts": "2026-07-02T11:00:00Z", "findings_received": 4, "must_fix_count": 2, "good_to_fix_count": 2, "refix_plans_written": 1}
    }
  }
}
EOF

JSON_OUT="$(python3 "$CLI" "$T/repo2" --json 2>/tmp/verify47-scoreboard.err)"
echo "$JSON_OUT" | python3 -m json.tool >/dev/null 2>&1 && pass "scoreboard: 통합 파일 --json 유효" || fail "scoreboard: --json 무효"
[ -s /tmp/verify47-scoreboard.err ] && fail "scoreboard: 정상 파일인데 stderr 경고 발생 ($(cat /tmp/verify47-scoreboard.err))" || pass "scoreboard: 정상 파일 경고 없음"

echo "$JSON_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["reviewers"]["qwen"]["must_fix"]==2' \
    && pass "scoreboard: reviewers 축 정확히 집계" || fail "scoreboard: reviewers 축 집계 오류"
echo "$JSON_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["coders"]["sonnet5"]["loc_added"]==100' \
    && pass "scoreboard: coders 축 정확히 집계" || fail "scoreboard: coders 축 집계 오류"

# 리뷰 사이클 없는(coder 전용) 파일은 경고 없이 조용히 reviewers 집계에서만 빠짐
cat > "$T/repo2/issues/issue-94__TYPE-agent-stats.json" <<'EOF'
{"issue": 94, "started": "2026-07-03T00:00:00Z", "coders": {"sonnet5": {"model": "Claude Sonnet 5"}}}
EOF
OUT2="$(python3 "$CLI" "$T/repo2" 2>/tmp/verify47-scoreboard2.err)"
grep -q "issue-94" /tmp/verify47-scoreboard2.err && fail "scoreboard: 리뷰 없는 정상 파일을 손상으로 오판" || pass "scoreboard: 리뷰 없는 정상 파일 경고 없음"

# --since는 started 기준
SINCE_CYCLES="$(python3 "$CLI" "$T/repo2" --json --since 2026-07-02 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["cycles"])')"
[ "$SINCE_CYCLES" = "0" ] && pass "scoreboard: --since가 started 기준으로 필터링" || fail "scoreboard: --since 오동작 (cycles=$SINCE_CYCLES)"

# ----- 5. aacp.sh — __TYPE-* 일괄 아카이브 -----
T2="$(mktemp -d)"
trap 'rm -rf "$T" "$T2"' EXIT
(
  cd "$T2"
  git init -q
  git config user.email "verify47@test.local"
  git config user.name "verify47"
  mkdir -p issues .claude/skills/aacpd
  cp -r "$REPO_ROOT/.claude/skills/aacpd/defaults" .claude/skills/aacpd/
  cp "$AACP" .claude/skills/aacpd/aacp.sh
  chmod +x .claude/skills/aacpd/aacp.sh

  cat > issues/issue-95.md <<'EOF'
# issue-95: verify-47 fixture
**구현 완료 일시**: 2026-07-13T00:00:00Z
EOF
  started="$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(minutes=10)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  cat > "issues/issue-95__TYPE-agent-stats.json" <<EOF2
{"issue": 95, "started": "$started", "coders": {"sonnet5": {"model": "Claude Sonnet 5"}}}
EOF2
  echo "Claude Sonnet 5" > "issues/issue-95__TYPE-code-review__BY-self.md"

  git add -A
  git commit -q -m "init"

  bash .claude/skills/aacpd/aacp.sh 95 "verify-47 test" >/tmp/verify47-aacp.out 2>&1
)
ARCHIVED_STATS="$(find "$T2/issues/archive" -name "issue-95__TYPE-agent-stats.json" 2>/dev/null)"
ARCHIVED_REVIEW="$(find "$T2/issues/archive" -name "issue-95__TYPE-code-review__BY-self.md" 2>/dev/null)"
[ -n "$ARCHIVED_STATS" ] && pass "aacp: agent-stats.json 아카이브됨" || fail "aacp: agent-stats.json 아카이브 안 됨 ($(cat /tmp/verify47-aacp.out 2>/dev/null))"
[ -n "$ARCHIVED_REVIEW" ] && pass "aacp: code-review 파일도 함께 아카이브됨" || fail "aacp: code-review 파일 아카이브 안 됨"
if [ -n "$ARCHIVED_STATS" ]; then
    python3 -c "import json; d=json.load(open('$ARCHIVED_STATS')); assert 'archived' in d and 'duration' in d" \
        && pass "aacp: 아카이브 전 archived/duration 채워짐" || fail "aacp: archived/duration 안 채워짐"
fi

# ----- 6. 단위 테스트 -----
if uv run --with pytest pytest -q "$REPO_ROOT/tests/test_agent_stats_archive.py" "$REPO_ROOT/tests/test_reviewer_scoreboard.py" "$REPO_ROOT/tests/test_reviewer_scoreboard_coder.py" >/tmp/verify47-pytest.out 2>&1; then
    pass "pytest 단위 테스트 통과"
else
    fail "pytest 단위 테스트 실패: $(tail -20 /tmp/verify47-pytest.out)"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-47 acceptance checks passed."
    exit 0
else
    echo "One or more issue-47 acceptance checks failed."
    exit 1
fi
