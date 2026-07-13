#!/usr/bin/env bash
# verify-issue-45.sh — coder-stats 인프라 (log-run 래퍼 + scoreboard coder 섹션)
# - log-run.sh: ruff/pyright 파싱 정확성, exit 전파, JSONL 한 줄 append
# - tools/reviewer-scoreboard.py: coder 섹션 (defect 밀도/1000라인, syntax 별도, run 횟수)
# - SKILL.md·spec: coder-stats TYPE enum / tdd2 log-run 경유 / autotddreview TYPE 목록
# - 단위 테스트: 파서/집계 모두 통과
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_REVIEW="$REPO_ROOT/.claude/skills/autotddreview/SKILL.md"
SKILL_TDD2="$HOME/.claude/skills/tdd2/SKILL.md"
SPEC="$REPO_ROOT/docs/spec/spec-issue-filenames.md"
CLI="$REPO_ROOT/tools/reviewer-scoreboard.py"
LOG_RUN="$REPO_ROOT/.claude/skills/acpd/defaults/log-run.sh"

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

# 1) 스펙 문서 — TYPE enum + 산출물 예시
has "$SPEC" "coder-stats" "spec: TYPE enum에 coder-stats 추가"
has "$SPEC" "issue-21__TYPE-coder-stats.jsonl" "spec: coder-stats 산출물 예시"

# 2) tdd2 SKILL.md — 시작 HEAD / log-run 경유 / pytest 비계측 / summary append
has "$SKILL_TDD2" "시작HEAD" "tdd2: 시작 HEAD 기록"
has "$SKILL_TDD2" "log-run.sh" "tdd2: log-run 경유 명시"
has "$SKILL_TDD2" "pytest / 회귀 스크립트는 계측하지 않는다" "tdd2: pytest 비계측"
has "$SKILL_TDD2" "summary" "tdd2: summary 라인 append"

# 3) autotddreview SKILL.md — coder-stats.jsonl TYPE 목록 포함
has "$SKILL_REVIEW" "coder-stats.jsonl" "autotddreview: coder-stats.jsonl TYPE 목록"

# 4) log-run.sh — 실제 호출 테스트
[ -x "$LOG_RUN" ] && pass "log-run.sh 존재/실행가능" || fail "log-run.sh 부재 또는 비실행: $LOG_RUN"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/issues"

# 가짜 ruff — 3 errors, 1 fixed, 1 E999 라인
cat > "$T/fake-ruff.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake.py:5:1: E501 line-too-long"
echo "fake.py:10:1: E501 line-too-long"
echo "fake.py:1:1: E999 SyntaxError: invalid syntax"
echo "Found 3 errors (1 fixed, 2 remaining)."
exit 1
EOF
chmod +x "$T/fake-ruff.sh"

# 가짜 pyright — 2 errors
cat > "$T/fake-pyright.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake.py:5: error: type mismatch"
echo "fake.py:10: error: missing arg"
echo "  2 errors, 1 warning, 0 notes"
exit 1
EOF
chmod +x "$T/fake-pyright.sh"

# 가짜 출력 식별 불가
cat > "$T/fake-broken.sh" <<'EOF'
#!/usr/bin/env bash
echo "no recognized markers"
exit 0
EOF
chmod +x "$T/fake-broken.sh"

# 실행: cd로 T를 작업 디렉토리로 잡고 호출
pushd "$T" >/dev/null
RUFF_OUT=$(bash "$LOG_RUN" 99 ruff ./fake-ruff.sh 2>&1); RUFF_RC=$?
PYRIGHT_OUT=$(bash "$LOG_RUN" 99 pyright ./fake-pyright.sh 2>&1); PYRIGHT_RC=$?
BROKEN_OUT=$(bash "$LOG_RUN" 99 ruff ./fake-broken.sh 2>&1); BROKEN_RC=$?
popd >/dev/null

[ $RUFF_RC -eq 1 ] && pass "log-run: ruff exit code 1 전파" || fail "log-run: ruff exit=$RUFF_RC (expected 1)"
[ $PYRIGHT_RC -eq 1 ] && pass "log-run: pyright exit code 1 전파" || fail "log-run: pyright exit=$PYRIGHT_RC (expected 1)"
[ $BROKEN_RC -eq 0 ] && pass "log-run: parse-failure exit code 0 전파" || fail "log-run: parse-failure exit=$BROKEN_RC (expected 0)"

# stdout 패스스루 (사용자 출력이 그대로 보임)
echo "$RUFF_OUT" | grep -q "Found 3 errors" && pass "log-run: stdout 패스스루" || fail "log-run: stdout 누락"

# JSONL 검증
JSONL="$T/issues/issue-99__TYPE-coder-stats.jsonl"
[ -f "$JSONL" ] && pass "log-run: JSONL 파일 생성" || fail "log-run: JSONL 미생성"
LINES=$(wc -l < "$JSONL")
[ "$LINES" -eq 3 ] && pass "log-run: 3줄 append" || fail "log-run: line count=$LINES (expected 3)"

# ruff 라인: errors=3, fixed=1, syntax_errors=1
RUFF_LINE=$(grep '"tool":"ruff"' "$JSONL" | head -1)
echo "$RUFF_LINE" | grep -q '"errors":3' && pass "log-run: ruff errors=3" || fail "log-run: ruff errors 추출 실패: $RUFF_LINE"
echo "$RUFF_LINE" | grep -q '"fixed":1' && pass "log-run: ruff fixed=1" || fail "log-run: ruff fixed 추출 실패"
echo "$RUFF_LINE" | grep -q '"syntax_errors":1' && pass "log-run: ruff syntax_errors=1" || fail "log-run: ruff E999 카운트 실패"

# pyright 라인: errors=2
PYRIGHT_LINE=$(grep '"tool":"pyright"' "$JSONL" | head -1)
echo "$PYRIGHT_LINE" | grep -q '"errors":2' && pass "log-run: pyright errors=2" || fail "log-run: pyright errors 추출 실패"

# parse-failure 라인: errors=null, fixed=null, syntax_errors=0
BROKEN_LINE=$(grep '"tool":"ruff"' "$JSONL" | tail -1)
echo "$BROKEN_LINE" | grep -q '"errors":null' && pass "log-run: parse-failure errors=null" || fail "log-run: parse-failure errors 미null: $BROKEN_LINE"
echo "$BROKEN_LINE" | grep -q '"fixed":null' && pass "log-run: parse-failure fixed=null" || fail "log-run: parse-failure fixed 미null"
echo "$BROKEN_LINE" | grep -q '"syntax_errors":0' && pass "log-run: parse-failure syntax_errors=0" || fail "log-run: parse-failure syntax_errors 미0"

# 5) scoreboard coder 섹션 — 픽스처로 defect 밀도/1000라인 단언
T2="$(mktemp -d)"
mkdir -p "$T2/repo/issues"
cat > "$T2/repo/issues/issue-21__TYPE-coder-stats.jsonl" <<'EOF'
{"kind":"summary","ts":"2026-07-01T10:00:00","coder":"sonnet","model":"Claude Sonnet 4.6","loc_added":60}
{"kind":"run","ts":"2026-07-01T10:01:00","tool":"ruff","exit":1,"errors":10,"fixed":2,"syntax_errors":0}
EOF
JSON_OUT=$(python3 "$CLI" "$T2/repo" --json 2>/dev/null)
echo "$JSON_OUT" | python3 -m json.tool >/dev/null 2>&1 && pass "scoreboard --json 유효" || fail "scoreboard --json 무효"
DENSITY=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["sonnet"]["defect_density_per_kloc"])')
[ "$DENSITY" = "200.0" ] && pass "scoreboard: defect 밀도 200.0/kloc" || fail "scoreboard: density=$DENSITY (expected 200.0)"
RUNS=$(echo "$JSON_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["coders"]["sonnet"]["runs"])')
[ "$RUNS" = "1" ] && pass "scoreboard: run 횟수 1" || fail "scoreboard: runs=$RUNS (expected 1)"

# syntax_errors 별도 컬럼 — defect 밀도에 합산 안 됨 (별도 카운트)
T3="$(mktemp -d)"
mkdir -p "$T3/repo/issues"
cat > "$T3/repo/issues/issue-21__TYPE-coder-stats.jsonl" <<'EOF'
{"kind":"summary","ts":"2026-07-01T10:00:00","coder":"deepseek","model":"deepseek-v3","loc_added":100}
{"kind":"run","ts":"2026-07-01T10:01:00","tool":"ruff","exit":1,"errors":4,"fixed":0,"syntax_errors":2}
EOF
SYN_DENSITY=$(python3 "$CLI" "$T3/repo" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin)["coders"]["deepseek"]; print(d["defect_density_per_kloc"], d["syntax_errors"])')
[ "$SYN_DENSITY" = "40.0 2" ] && pass "scoreboard: syntax 별도, density=40.0/kloc" || fail "scoreboard: syntax 분리 실패: $SYN_DENSITY"

# 6) 단위 테스트
if uv run --with pytest pytest -q "$REPO_ROOT/tests/" >/dev/null 2>&1; then
    pass "pytest 단위 테스트 통과 (reviewer + coder)"
else
    fail "pytest 단위 테스트 실패"
fi

rm -rf "$T2" "$T3"

if [ $FAIL -eq 0 ]; then
    echo "All issue-45 acceptance checks passed."
    exit 0
else
    echo "One or more issue-45 acceptance checks failed."
    exit 1
fi