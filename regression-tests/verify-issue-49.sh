#!/usr/bin/env bash
# verify-issue-49.sh — agent-stats.json cost_details/cost_summary 계측
# (log-cost-<base>.py 8개, log-cost-summary.py, tdd2/autotddreview/acpd
# SKILL.md 훅) 검증.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_TDD2="$REPO_ROOT/.claude/skills/tdd2/SKILL.md"
SKILL_REVIEW="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"
SKILL_ACPD="$REPO_ROOT/.claude/skills/acpd/SKILL.md"
AACP="$REPO_ROOT/.claude/skills/acpd/aacp.sh"
COST_ENTRY="$REPO_ROOT/tools/cost_entry.py"

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

# ----- 1. 스크립트 + uv run wrapper(.sh/.bat/.ps1) 존재 -----
[ -f "$COST_ENTRY" ] && pass "cost_entry.py 존재" || fail "cost_entry.py 부재"
for base in sonnet opus haiku fable gemini minimax qwen deepseek summary; do
    for ext in py sh bat ps1; do
        f="$REPO_ROOT/tools/log-cost-$base.$ext"
        [ -f "$f" ] && pass "log-cost-$base.$ext 존재" || fail "log-cost-$base.$ext 부재"
    done
done
[ -x "$REPO_ROOT/tools/log-cost-sonnet.sh" ] && pass "log-cost-sonnet.sh 실행 권한 있음" || fail "log-cost-sonnet.sh 실행 권한 없음"

# ----- 2. SKILL.md 훅 문구 -----
has "$SKILL_TDD2" "before mvp" "tdd2: before mvp 계측 지시"
has "$SKILL_TDD2" "after mvp" "tdd2: after mvp 계측 지시"
has "$SKILL_REVIEW" "before review" "autotddreview: before review 계측 지시"
has "$SKILL_REVIEW" "after review" "autotddreview: after review 계측 지시"
has "$SKILL_REVIEW" "before refix-plan" "autotddreview: before refix-plan 계측 지시"
has "$SKILL_REVIEW" "after refix-plan" "autotddreview: after refix-plan 계측 지시"
has "$SKILL_REVIEW" "before refix" "autotddreview: before refix 계측 지시"
has "$SKILL_REVIEW" "after refix" "autotddreview: after refix 계측 지시"
has "$AACP" "log-cost-summary.py" "aacp.sh: log-cost-summary.py 호출"
has "$SKILL_ACPD" "log-cost-summary.py" "acpd/SKILL.md: log-cost-summary.py 문서화"

# SKILL.md는 pydantic 의존성 때문에 반드시 uv run wrapper(.sh)를 호출해야
# 한다 — 맨 .py를 직접 부르면 uv 없이 실행될 경우 ModuleNotFoundError.
not_has() {
    local file="$1" pattern="$2" desc="$3"
    if grep -qF -e "$pattern" "$file" 2>/dev/null; then
        fail "존재하면 안 됨: $desc"
    else
        pass "$desc"
    fi
}
has "$SKILL_TDD2" "log-cost-<base명>.sh <repo-path>" "tdd2: .sh wrapper 호출"
not_has "$SKILL_TDD2" ".py <repo-path>" "tdd2: 맨 .py 직접 호출(repo-path 인자) 0건"
has "$SKILL_REVIEW" ".sh <repo-path>" "autotddreview: .sh wrapper 호출"
not_has "$SKILL_REVIEW" ".py <repo-path>" "autotddreview: 맨 .py 직접 호출(repo-path 인자) 0건"

# ----- 3. 스크래치 픽스처로 실제 스크립트 동작 검증 (SKILL.md가 실제로
# 부르는 .sh wrapper 경유) -----
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/issues"
cat > "$T/repo/issues/issue-90__TYPE-agent-stats.json" <<'EOF'
{"issue": 90, "started": "2026-07-13T09:00:00Z", "coders": {"sonnet": {"model": "claude-sonnet-5"}}}
EOF

"$REPO_ROOT/tools/log-cost-sonnet.sh" "$T/repo" issue-90 "before mvp" >/tmp/verify49-sonnet.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-sonnet.sh: 정상 exit 0" || fail "log-cost-sonnet.sh exit $RC: $(cat /tmp/verify49-sonnet.out)"

"$REPO_ROOT/tools/log-cost-minimax.sh" "$T/repo" issue-90 "before review" >/tmp/verify49-minimax.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-minimax.sh: 정상 exit 0" || fail "log-cost-minimax.sh exit $RC: $(cat /tmp/verify49-minimax.out)"

python3 - "$T/repo/issues/issue-90__TYPE-agent-stats.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
details = data.get("cost_details", [])
assert len(details) == 2, f"cost_details 길이={len(details)} (2 기대)"
sonnet = next(d for d in details if d["model"] == "sonnet")
minimax = next(d for d in details if d["model"] == "minimax")
assert sonnet["description"] == "before mvp"
assert minimax["five_hour_used_pct"] is None and minimax["seven_day_used_pct"] is None, "minimax는 null이어야 함"
assert minimax["description"] == "before review"
print("OK")
PYEOF
[ $? -eq 0 ] && pass "cost_details: sonnet 실측 + minimax null 정확히 기록" || fail "cost_details 내용 검증 실패"

# --dryrun은 파일을 바꾸지 않는다
BEFORE_HASH="$(md5sum "$T/repo/issues/issue-90__TYPE-agent-stats.json" | cut -d' ' -f1)"
"$REPO_ROOT/tools/log-cost-sonnet.sh" --dryrun "$T/repo" issue-90 "after mvp (dryrun)" >/tmp/verify49-dryrun.out 2>&1
AFTER_HASH="$(md5sum "$T/repo/issues/issue-90__TYPE-agent-stats.json" | cut -d' ' -f1)"
[ "$BEFORE_HASH" = "$AFTER_HASH" ] && pass "--dryrun: 파일 불변" || fail "--dryrun인데 파일이 변경됨"
grep -q "dryrun" /tmp/verify49-dryrun.out && pass "--dryrun: 출력에 dryrun 표시" || fail "--dryrun 출력에 표시 없음"

# ----- 4. log-cost-summary.sh — 합산 정확성 -----
"$REPO_ROOT/tools/log-cost-summary.sh" "$T/repo" issue-90 >/tmp/verify49-summary.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-summary.sh: 정상 exit 0" || fail "log-cost-summary.sh exit $RC: $(cat /tmp/verify49-summary.out)"

python3 - "$T/repo/issues/issue-90__TYPE-agent-stats.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
summary = data.get("cost_summary", {})
assert "sonnet" in summary and "minimax" in summary, f"cost_summary 키 누락: {summary}"
assert summary["minimax"]["five_hour_sum"] is None, "minimax는 전부 null이므로 합산도 null이어야 함"
assert isinstance(summary["sonnet"]["five_hour_sum"], (int, float)), "sonnet 실측값은 숫자여야 함"
print("OK")
PYEOF
[ $? -eq 0 ] && pass "cost_summary: 모델별 합산 정확(null 제외 처리 포함)" || fail "cost_summary 내용 검증 실패"

# ----- 5. aacp.sh 전체 훅 흐름 (임시 git repo) -----
T2="$(mktemp -d)"
trap 'rm -rf "$T" "$T2"' EXIT
(
  cd "$T2"
  git init -q
  git config user.email "verify49@test.local"
  git config user.name "verify49"
  mkdir -p issues .claude/skills/acpd
  cp -r "$REPO_ROOT/.claude/skills/acpd/defaults" .claude/skills/acpd/
  cp "$AACP" .claude/skills/acpd/aacp.sh
  chmod +x .claude/skills/acpd/aacp.sh
  mkdir -p tools
  cp "$REPO_ROOT/tools/log-cost-summary.py" tools/

  cat > issues/issue-96.md <<'EOF'
# issue-96: verify-49 fixture
**구현 완료 일시**: 2026-07-13T00:00:00Z
EOF
  started="$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  cat > "issues/issue-96__TYPE-agent-stats.json" <<EOF2
{"issue": 96, "started": "$started", "coders": {"sonnet": {"model": "claude-sonnet-5"}}, "cost_details": [{"ts": "$started", "model": "sonnet", "five_hour_used_pct": 10.0, "seven_day_used_pct": 20.0, "description": "before mvp"}]}
EOF2

  git add -A
  git commit -q -m "init"

  bash .claude/skills/acpd/aacp.sh 96 "verify-49 test" >/tmp/verify49-aacp.out 2>&1
)
ARCHIVED_STATS="$(find "$T2/issues/archive" -name "issue-96__TYPE-agent-stats.json" 2>/dev/null)"
[ -n "$ARCHIVED_STATS" ] && pass "aacp: agent-stats.json 아카이브됨" || fail "aacp: agent-stats.json 아카이브 안 됨 ($(cat /tmp/verify49-aacp.out 2>/dev/null))"
if [ -n "$ARCHIVED_STATS" ]; then
    python3 -c "
import json
d = json.load(open('$ARCHIVED_STATS'))
assert 'cost_summary' in d, 'cost_summary 없음'
assert d['cost_summary']['sonnet']['five_hour_sum'] == 10.0, d['cost_summary']
assert 'archived' in d and 'duration' in d, 'archived/duration 없음'
print('OK')
" && pass "aacp: cost_summary가 archived/duration과 함께 채워짐" || fail "aacp: cost_summary 검증 실패"
fi

if [ $FAIL -eq 0 ]; then
    echo "All issue-49 acceptance checks passed."
    exit 0
else
    echo "One or more issue-49 acceptance checks failed."
    exit 1
fi
