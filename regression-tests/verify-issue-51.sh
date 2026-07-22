#!/usr/bin/env bash
# verify-issue-51.sh — aacpd deploy 탐색: deploy-to-dev.sh가 deploy.sh보다
# 우선하고, deploy-to-env.sh(오타) 관련 코드/문서가 전부 제거됐는지 검증.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AACP="$REPO_ROOT/skills/aacpd/aacp.sh"
SKILL_AACPD="$REPO_ROOT/skills/aacpd"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# ----- 0. deploy-to-env 문자열이 스킬 디렉토리 어디에도 없어야 함 -----
if grep -rlF "deploy-to-env" "$SKILL_AACPD" >/dev/null 2>&1; then
  fail "aacpd 스킬 디렉토리에 deploy-to-env 문자열이 남아있음"
else
  pass "aacpd 스킬 디렉토리에 deploy-to-env 문자열 없음"
fi

# ----- fixture 헬퍼: 임시 git repo + issue-1.md + 더미 deploy 스크립트 -----
make_fixture() {
  local dir bare
  dir="$(mktemp -d)"
  bare="$(mktemp -d)"
  git init -q --bare "$bare"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" remote add origin "$bare"
  mkdir -p "$dir/issues"
  cat > "$dir/issues/issue-1.md" <<'EOF'
# issue-1: dummy
## 구현 결과
- **구현 완료 일시**: 2026-01-01T00:00:00-00:00
- **변경 파일**: none
- **계획 대비 편차**: 없음
- **검증 결과**: n/a
EOF
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  git -C "$dir" push -q -u origin HEAD
  echo "$dir"
}

run_aacp() {
  local dir="$1"
  (cd "$dir" && bash "$AACP" 1 "test summary" >"$dir/.aacp.out" 2>&1)
}

# ----- 1. deploy-to-dev.sh만 있음 -----
d1="$(make_fixture)"
cat > "$d1/deploy-to-dev.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy-to-dev" > "$(dirname "$0")/.deploy-marker"
EOF
chmod +x "$d1/deploy-to-dev.sh"
git -C "$d1" add deploy-to-dev.sh && git -C "$d1" commit -q -m "add deploy-to-dev.sh"
run_aacp "$d1"
if [ "$(cat "$d1/.deploy-marker" 2>/dev/null)" = "deploy-to-dev" ]; then
  pass "deploy-to-dev.sh만 있을 때 그것만 호출됨"
else
  fail "deploy-to-dev.sh만 있을 때 호출되지 않음 (출력: $(cat "$d1/.aacp.out" 2>/dev/null))"
fi

# ----- 2. deploy-to-dev.sh + deploy.sh 둘 다 있음 -> deploy-to-dev.sh 우선 -----
d2="$(make_fixture)"
cat > "$d2/deploy-to-dev.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy-to-dev" > "$(dirname "$0")/.deploy-marker"
EOF
cat > "$d2/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy: $*" > "$(dirname "$0")/.deploy-marker"
EOF
chmod +x "$d2/deploy-to-dev.sh" "$d2/deploy.sh"
git -C "$d2" add deploy-to-dev.sh deploy.sh && git -C "$d2" commit -q -m "add both"
run_aacp "$d2"
if [ "$(cat "$d2/.deploy-marker" 2>/dev/null)" = "deploy-to-dev" ]; then
  pass "deploy-to-dev.sh와 deploy.sh 둘 다 있을 때 deploy-to-dev.sh 우선 호출"
else
  fail "우선순위 위반: $(cat "$d2/.deploy-marker" 2>/dev/null)"
fi

# ----- 3. deploy.sh만 있음 -> --env dev로 호출 -----
d3="$(make_fixture)"
cat > "$d3/deploy.sh" <<'EOF'
#!/usr/bin/env bash
echo "deploy: $*" > "$(dirname "$0")/.deploy-marker"
EOF
chmod +x "$d3/deploy.sh"
git -C "$d3" add deploy.sh && git -C "$d3" commit -q -m "add deploy.sh"
run_aacp "$d3"
if [ "$(cat "$d3/.deploy-marker" 2>/dev/null)" = "deploy: --env dev" ]; then
  pass "deploy.sh만 있을 때 --env dev로 호출됨"
else
  fail "deploy.sh 인자 전달 오류: $(cat "$d3/.deploy-marker" 2>/dev/null)"
fi

# ----- 4. 아무 배포 스크립트도 없음 -> skip, exit 0 -----
d4="$(make_fixture)"
if (cd "$d4" && bash "$AACP" 1 "test summary" >"$d4/.aacp.out" 2>&1); then
  pass "배포 스크립트 없을 때 exit 0 (skip)"
else
  fail "배포 스크립트 없을 때 실패해서는 안 됨"
fi
if grep -q "no deploy-to-dev.sh or deploy.sh" "$d4/.aacp.out"; then
  pass "배포 스크립트 없을 때 안내 메시지 출력"
else
  fail "안내 메시지 없음: $(cat "$d4/.aacp.out")"
fi

rm -rf "$d1" "$d2" "$d3" "$d4"

exit $FAIL
