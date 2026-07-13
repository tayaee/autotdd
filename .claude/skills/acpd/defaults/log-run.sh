#!/usr/bin/env bash
# log-run.sh — 정적분석 도구 호출을 감싸 coder-stats JSONL에 기록 (issue-45)
#
# 사용법:
#   log-run.sh <이슈번호> <tool명> <실제 스크립트> [인자...]
#
# - 실제 스크립트를 실행하고 stdout/stderr는 그대로 통과(투명 래퍼)
# - exit code도 그대로 전파
# - 출력을 파싱해 issues/issue-<N>__TYPE-coder-stats.jsonl에 한 줄 append:
#     {"kind":"run","ts":<ISO8601>,"tool":<tool명>,"exit":<code>,
#      "errors":<수>,"fixed":<수>,"syntax_errors":<수>}
# - 파싱 규칙 (도구 표준 출력 기준):
#     ruff    : `Found N errors (M fixed, ...)`에서 errors·fixed,
#               E999 라인 수 → syntax_errors
#     pyright : 말미 `X errors, Y warnings ...`에서 X → errors
# - 파싱 실패 시 errors/fixed/syntax_errors는 null로 기록하되 라인은 남김
#   (침묵 금지)
# - issue-45 스펙: pytest/회귀는 계측 제외. 이 래퍼는 ruff/pyright 전용.

set -u

if [ "$#" -lt 3 ]; then
    echo "사용법: log-run.sh <이슈번호> <tool명> <실제 스크립트> [인자...]" >&2
    exit 64
fi

ISSUE_N="$1"
TOOL="$2"
shift 2

if ! [[ "$ISSUE_N" =~ ^[0-9]+$ ]]; then
    echo "ERROR: 이슈 번호는 정수여야 합니다: '$ISSUE_N'" >&2
    exit 64
fi

# CWD = repo root 가정 (acpd의 다른 defaults와 동일 관행)
ISSUES_DIR="issues"
if [ ! -d "$ISSUES_DIR" ]; then
    echo "ERROR: $ISSUES_DIR 디렉토리가 없습니다 — repo 루트에서 실행하세요" >&2
    exit 64
fi
JSONL="$ISSUES_DIR/issue-${ISSUE_N}__TYPE-coder-stats.jsonl"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)"

# 실제 스크립트 실행 — stdout+stderr 캡처용 임시 파일
TMP_OUT="$(mktemp)"
TMP_ERR="$(mktemp)"
trap 'rm -f "$TMP_OUT" "$TMP_ERR"' EXIT

# 사용자 스크립트 실행 (subshell 우회, stdin 그대로 유지)
"$@" >"$TMP_OUT" 2>"$TMP_ERR"
EXIT_CODE=$?

COMBINED="$(cat "$TMP_OUT" "$TMP_ERR" 2>/dev/null)"

# 사용자 출력은 그대로 통과 (stdout 먼저, stderr은 원본 순서 유지)
cat "$TMP_OUT"
cat "$TMP_ERR" >&2

# 파싱 — 도구별 규칙
parse_ruff() {
    # ruff: "Found N errors (M fixed, ...)" 패턴에서 errors·fixed 추출
    # 형식 예: "Found 3 errors (1 fixed, 2 remaining)."
    local out="$1"
    local err="" fix="" syn=0
    # E999 라인 수 (기초 실수) — 매치 없으면 0
    syn=$(printf '%s\n' "$out" | grep -cE '^(.*:.*:)?\s*E999\b' || true)
    [ -z "$syn" ] && syn=0
    # Found N errors (M fixed, ...) 패턴 — PCRE 매칭이 가장 안정적.
    # GNU sed의 ERE greedy `.*\)` 패턴이 trailing 문자를 섞는 함정이 있어
    # grep -oP + 숫자 추출의 2단계로 분리한다.
    local found_line
    found_line=$(printf '%s\n' "$out" | grep -E 'Found [0-9]+ errors?' | head -1 || true)
    if [ -n "$found_line" ]; then
        err=$(printf '%s' "$found_line" | grep -oP 'Found \K[0-9]+' | head -1 || true)
        fix=$(printf '%s' "$found_line" | grep -oP '\(\K[0-9]+(?= fixed)' | head -1 || true)
    fi
    # 파싱 실패 → null (침묵 금지 정책)
    [ -z "$err" ] && err=null
    [ -z "$fix" ] && fix=null
    echo "$err|$fix|$syn"
}

parse_pyright() {
    # pyright: "... 3 errors, 2 warnings, 1 note" 패턴
    local out="$1"
    local err=""
    err=$(printf '%s\n' "$out" | grep -oE '[0-9]+ errors?' | head -1 | grep -oE '[0-9]+' || true)
    [ -z "$err" ] && err=null
    echo "$err|null|null"
}

case "$TOOL" in
    ruff)
        parsed=$(parse_ruff "$COMBINED")
        ERR=$(echo "$parsed" | cut -d'|' -f1)
        FIX=$(echo "$parsed" | cut -d'|' -f2)
        SYN=$(echo "$parsed" | cut -d'|' -f3)
        ;;
    pyright)
        parsed=$(parse_pyright "$COMBINED")
        ERR=$(echo "$parsed" | cut -d'|' -f1)
        FIX="null"
        SYN="null"
        ;;
    *)
        # 알 수 없는 도구 — 파싱 없이 null
        ERR="null"; FIX="null"; SYN="null"
        ;;
esac

# 빈 문자열 → null (sed가 매치 못하면 비어있음)
[ -z "$ERR" ] && ERR="null"
[ -z "$FIX" ] && FIX="null"
[ -z "$SYN" ] && SYN="null"

# JSONL append (한 줄, 들여쓰기 없음)
printf '{"kind":"run","ts":"%s","tool":"%s","exit":%d,"errors":%s,"fixed":%s,"syntax_errors":%s}\n' \
    "$TS" "$TOOL" "$EXIT_CODE" "$ERR" "$FIX" "$SYN" >> "$JSONL"

exit "$EXIT_CODE"