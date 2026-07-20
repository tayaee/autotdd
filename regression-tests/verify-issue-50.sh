#!/usr/bin/env bash
# verify-issue-50.sh — agent-stats.json cost_details/cost_summary 계측
# (log-cost-<base>.py 8개, log-cost-summary.py, tdd2/autotddreviewfix/aacpd
# SKILL.md 훅). issue-49 재도입 — 모델명은 매번 실행 세션이 파라미터로
#결정(하드코딩 금지)하되 정확해야 한다는 제약 검증 포함.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_TDD2="$REPO_ROOT/skills/tdd2/SKILL.md"
SKILL_REVIEW="$REPO_ROOT/skills/autotddreviewfix/SKILL.md"
SKILL_AACPD="$REPO_ROOT/skills/aacpd/SKILL.md"
AACP="$REPO_ROOT/skills/aacpd/aacp.sh"
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

not_has() {
    local file="$1" pattern="$2" desc="$3"
    if grep -qF -e "$pattern" "$file" 2>/dev/null; then
        fail "존재하면 안 됨: $desc"
    else
        pass "$desc"
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
has "$SKILL_REVIEW" "before review" "autotddreviewfix: before review 계측 지시"
has "$SKILL_REVIEW" "after review" "autotddreviewfix: after review 계측 지시"
has "$SKILL_REVIEW" "before refix-plan" "autotddreviewfix: before refix-plan 계측 지시"
has "$SKILL_REVIEW" "after refix-plan" "autotddreviewfix: after refix-plan 계측 지시"
has "$SKILL_REVIEW" "before refix" "autotddreviewfix: before refix 계측 지시"
has "$SKILL_REVIEW" "after refix" "autotddreviewfix: after refix 계측 지시"
has "$AACP" "log-cost-summary.py" "aacp.sh: log-cost-summary.py 호출"
has "$SKILL_AACPD" "log-cost-summary.py" "aacpd/SKILL.md: log-cost-summary.py 문서화"

# SKILL.md는 pydantic 의존성 때문에 반드시 uv run wrapper(.sh)를 호출해야
# 한다 — 맨 .py를 직접 부르면 uv 없이 실행될 경우 ModuleNotFoundError.
has "$SKILL_TDD2" "log-cost-<base명>.sh <repo-path>" "tdd2: .sh wrapper 호출"
not_has "$SKILL_TDD2" ".py <repo-path>" "tdd2: 맨 .py 직접 호출(repo-path 인자) 0건"
has "$SKILL_REVIEW" ".sh <repo-path>" "autotddreviewfix: .sh wrapper 호출"
not_has "$SKILL_REVIEW" ".py <repo-path>" "autotddreviewfix: 맨 .py 직접 호출(repo-path 인자) 0건"

# ----- 2.5 모델명 정확성(issue-50 요구사항 0): SKILL.md 훅 지시문에
# base명이 리터럴로 하드코딩(예: log-cost-sonnet.sh처럼 특정 모델명이
# 파일명에 고정)되어 있으면 안 된다 — 항상 <base명>/<X> 같은 플레이스홀더.
not_has "$SKILL_TDD2" "log-cost-sonnet.sh" "tdd2: model 식별자 하드코딩(log-cost-sonnet.sh 리터럴) 없음"
not_has "$SKILL_REVIEW" "tools/log-cost-sonnet.sh <repo-path> issue-<N> \"before" "autotddreviewfix: model 식별자 하드코딩 없음"
has "$SKILL_TDD2" "정확히 동일한 값" "tdd2: 모델명 정확성(동일 값 재사용) 명시"
has "$SKILL_REVIEW" "정확히 같은 값" "autotddreviewfix: 모델명 정확성(동일 값 재사용) 명시"

# ----- 3. 스크래치 픽스처로 실제 스크립트 동작 검증 (SKILL.md가 실제로
# 부르는 .sh wrapper 경유) -----
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/issues"
cat > "$T/repo/issues/issue-90__agent-stats.json" <<'EOF'
{"issue": 90, "started": "2026-07-20T09:00:00-04:00", "coders": {"sonnet": {"model": "claude-sonnet-5"}}}
EOF

"$REPO_ROOT/tools/log-cost-sonnet.sh" "$T/repo" issue-90 "before mvp" >/tmp/verify50-sonnet.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-sonnet.sh: 정상 exit 0" || fail "log-cost-sonnet.sh exit $RC: $(cat /tmp/verify50-sonnet.out)"

"$REPO_ROOT/tools/log-cost-minimax.sh" "$T/repo" issue-90 "before review" >/tmp/verify50-minimax.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-minimax.sh: 정상 exit 0" || fail "log-cost-minimax.sh exit $RC: $(cat /tmp/verify50-minimax.out)"

python3 - "$T/repo/issues/issue-90__agent-stats.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
details = data.get("cost_details", [])
assert len(details) == 2, f"cost_details 길이={len(details)} (2 기대)"
sonnet = next(d for d in details if d["model"] == "sonnet")
minimax = next(d for d in details if d["model"] == "minimax")
assert sonnet["description"] == "before mvp"
assert minimax["five_hour_used_pct"] is None and minimax["seven_day_used_pct"] is None, "minimax는 null이어야 함"
assert minimax["description"] == "before review"
assert "+" in sonnet["ts"] or "-" in sonnet["ts"][10:], f"ts가 로컬 오프셋 포함 ISO8601이 아님(UTC Z 금지): {sonnet['ts']}"
assert not sonnet["ts"].endswith("Z"), f"ts가 UTC Z로 끝남 — 로컬 오프셋 규약 위반: {sonnet['ts']}"
print("OK")
PYEOF
[ $? -eq 0 ] && pass "cost_details: sonnet 실측 + minimax null 정확히 기록, ts 로컬 오프셋 규약 준수" || fail "cost_details 내용 검증 실패"

# --dryrun은 파일을 바꾸지 않는다
BEFORE_HASH="$(md5sum "$T/repo/issues/issue-90__agent-stats.json" | cut -d' ' -f1)"
"$REPO_ROOT/tools/log-cost-sonnet.sh" --dryrun "$T/repo" issue-90 "after mvp (dryrun)" >/tmp/verify50-dryrun.out 2>&1
AFTER_HASH="$(md5sum "$T/repo/issues/issue-90__agent-stats.json" | cut -d' ' -f1)"
[ "$BEFORE_HASH" = "$AFTER_HASH" ] && pass "--dryrun: 파일 불변" || fail "--dryrun인데 파일이 변경됨"
grep -q "dryrun" /tmp/verify50-dryrun.out && pass "--dryrun: 출력에 dryrun 표시" || fail "--dryrun 출력에 표시 없음"

# --dryrun은 대상 파일이 없어도 에러 없이 동작해야 한다 (issue-49에서
# 사용자가 직접 재현·보고했던 버그의 회귀 방지)
"$REPO_ROOT/tools/log-cost-haiku.sh" --dryrun "$T/repo" issue-999 "no such file" >/tmp/verify50-dryrun-nofile.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "--dryrun: 대상 파일 없어도 에러 없이 exit 0" || fail "--dryrun인데 파일 부재로 실패함: $(cat /tmp/verify50-dryrun-nofile.out)"

# ----- 4. log-cost-summary.sh — 합산 정확성 -----
"$REPO_ROOT/tools/log-cost-summary.sh" "$T/repo" issue-90 >/tmp/verify50-summary.out 2>&1
RC=$?
[ $RC -eq 0 ] && pass "log-cost-summary.sh: 정상 exit 0" || fail "log-cost-summary.sh exit $RC: $(cat /tmp/verify50-summary.out)"

python3 - "$T/repo/issues/issue-90__agent-stats.json" <<'PYEOF'
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
  git config user.email "verify50@test.local"
  git config user.name "verify50"
  mkdir -p issues skills/aacpd
  cp -r "$REPO_ROOT/skills/aacpd/defaults" skills/aacpd/
  cp "$AACP" skills/aacpd/aacp.sh
  chmod +x skills/aacpd/aacp.sh
  mkdir -p tools
  cp "$REPO_ROOT/tools/log-cost-summary.py" tools/

  cat > issues/issue-96.md <<'EOF'
# issue-96: verify-50 fixture
**구현 완료 일시**: 2026-07-20T00:00:00-04:00
EOF
  # NOTE: aacp.sh의 기존(이슈-50과 무관한) 버그 우회 — TYPE_FILES 배열의
  # `__refix-plan.md` 엔트리는 glob 메타문자가 없는 리터럴 경로라
  # nullglob이 적용되지 않는다. 파일이 없으면 `git mv`가 그대로 실패하므로
  # (순수 tdd2+aacpd 플로우처럼 refix-plan.md가 애초에 안 생기는 경우 전부
  # 영향받는 기존 결함), 이 픽스처에서는 더미 파일을 만들어 우회한다.
  echo "(verify-50 fixture placeholder)" > issues/issue-96__refix-plan.md
  started="$(python3 -c "from datetime import datetime, timedelta; print((datetime.now().astimezone() - timedelta(minutes=5)).isoformat(timespec='seconds'))")"
  cat > "issues/issue-96__agent-stats.json" <<EOF2
{"issue": 96, "started": "$started", "coders": {"sonnet": {"model": "claude-sonnet-5"}}, "cost_details": [{"ts": "$started", "model": "sonnet", "five_hour_used_pct": 10.0, "seven_day_used_pct": 20.0, "description": "before mvp"}]}
EOF2

  git add -A
  git commit -q -m "init"

  bash skills/aacpd/aacp.sh 96 "verify-50 test" >/tmp/verify50-aacp.out 2>&1
)
ARCHIVED_STATS="$(find "$T2/issues/archive" -name "issue-96__agent-stats.json" 2>/dev/null)"
[ -n "$ARCHIVED_STATS" ] && pass "aacp: agent-stats.json 아카이브됨" || fail "aacp: agent-stats.json 아카이브 안 됨 ($(cat /tmp/verify50-aacp.out 2>/dev/null))"
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
    echo "All issue-50 acceptance checks passed."
    exit 0
else
    echo "One or more issue-50 acceptance checks failed."
    exit 1
fi
