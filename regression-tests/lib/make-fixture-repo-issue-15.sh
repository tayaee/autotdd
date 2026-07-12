#!/usr/bin/env bash
# Extends the issue-15 acceptance fixture on top of make-fixture-repo.sh:
# creates issue files spanning every branch of the per-item decision tree
# (un-stamped + manual, un-stamped + local-ok, stamped paid-only, suffix
# variants, reservation-in-progress), plus an untracked dummy file at the
# human main tree root for the "main tree untouched" criterion.
#
# Prints the temp directory path as the last line of stdout (same contract
# as make-fixture-repo.sh).
set -euo pipefail

tmp_dir="$(bash "$(dirname "$0")/make-fixture-repo.sh" | tail -n 1)"
work="$tmp_dir/work"

# Human main tree: untracked dummy that must remain byte-identical for the
# full duration of any autofix run (verification grep against this file).
echo "human-main-tree-untouched" > "$work/UNTRACKED_DUMMY"

# -- autofix items -------------------------------------------------------------

# ① un-stamped → wrapper returns TIER: manual → must rename to __STATE-manual
cat > "$work/issues/autofix-1.md" <<'EOF'
# autofix-1: 수동 분류 기대
reported-by: harness-test@dummy 2026-07-10T12:00:00Z

EXPECT-TIER-MANUAL

## 배경
un-stamped item whose tier judgement must come back manual.

## 요구사항
1. wrapper가 TIER: manual 응답 → 원격 autofix-1.md가 autofix-1__STATE-manual.md로 rename
2. DISPATCH 라인 미출력

## 승인 기준
- [ ] git pull 후 autofix-1__STATE-manual.md가 존재하고 autofix-1.md가 부재
EOF

# ② un-stamped → wrapper returns TIER: local-ok → stamp + DISPATCH
cat > "$work/issues/autofix-2.md" <<'EOF'
# autofix-2: 로컬 처리
reported-by: harness-test@dummy 2026-07-10T12:00:00Z

EXPECT-TIER-LOCAL-OK

## 배경
un-stamped item whose tier judgement must come back local-ok.

## 요구사항
1. wrapper가 TIER: local-ok 응답 → 파일에 `agent-tier: local-ok` 추가 + push
2. 이어서 DISPATCH 라인 출력

## 승인 기준
- [ ] push 후 파일 첫 줄 근처에 `agent-tier: local-ok` 존재
- [ ] DISPATCH autofix-2 <래퍼> 한 줄 출력
EOF

# ③ already stamped paid-only → paid selection은 dispatch, local은 skip
cat > "$work/issues/autofix-3.md" <<'EOF'
# autofix-3: paid-only 전용
agent-tier: paid-only
reported-by: harness-test@dummy 2026-07-10T12:00:00Z

## 배경
already-stamped paid-only item.

## 요구사항
1. paid 선정 시 dispatch, local 선정 시 skip (DISPATCH 미출력, 파일 불변)

## 승인 기준
- [ ] local 래퍼 모드에서 파일 원문 불변 + DISPATCH 미출력
EOF

# ④ suffix variants — must be filtered out before any tier logic runs.
cat > "$work/issues/autofix-4__STATE-later.md" <<'EOF'
# autofix-4__STATE-later: 사람 보류
## 배경
later
EOF
cat > "$work/issues/autofix-5__STATE-manual.md" <<'EOF'
# autofix-5__STATE-manual: 사람 담당
## 배경
manual
EOF
cat > "$work/issues/autofix-6__STATE-agent-failed.md" <<'EOF'
# autofix-6__STATE-agent-failed: 직전 시도 실패
## 배경
agent-failed
EOF

# ⑤ reservation-in-progress (no `## ` section) — must be filtered too.
cat > "$work/issues/autofix-7.md" <<'EOF'
# autofix-7: 예약
reported-by: harness-test@dummy 2026-07-10T12:00:00Z
EOF

# commit + push to fixture origin so worktree sees them on creation.
git -C "$work" add -A
git -C "$work" commit -q -m "issue-15 fixture: items spanning every branch"
git -C "$work" push -q origin main

echo "$tmp_dir"
