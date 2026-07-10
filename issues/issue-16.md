# issue-16: autofix/autodev 디스패치 — 실행, 성공 판정, 실패 처리
agent-tier: paid-only

## 배경

issue-15의 `dispatch` 스텁을 실구현으로 교체한다. 명세:
`docs/autoqafix-design.md`의 "autofix / autodev" 2·4번과 CONTEXT.md "실패 기록".

## 요구사항

1. `dispatch(item, wrapper)` 실구현: worktree에서
   `<래퍼> -p "/autotdd <stream>-<N> worktree"` 실행, 타임아웃
   `AUTOQAFIX_IMPL_TIMEOUT`(기본 10800초). `run_with_timeout`(issue-10)을 사용해
   타임아웃 시 프로세스 트리 전체를 종료한다
2. 성공 판정: worktree에서 pull 후 `issues/<stream>-<N>.md`가 사라지고
   `issues/archive/**/<stream>-<N>.md`가 존재하면 성공
3. 실패/타임아웃: worktree를 `git -C <wt> reset --hard origin/main`으로 복구,
   `git worktree prune`. 항목 파일에 `## agent 실패 기록` 섹션(없으면 생성) +
   `- <ISO8601> <래퍼>: <exit code 또는 timeout, stderr 마지막 3줄>` 추가 →
   `-agent-failed`로 `git mv` → 그 파일만 commit·push → 다음 항목.
   승급 없음, 정체는 사람 개입
4. `FIXED=<n>` = 성공(archive 이동) 건수 (issue-15의 고정 `FIXED=0`을 실계수로
   대체)

## 승인 기준

픽스처 + fake-wrapper로:

- [ ] `agent-tier: local-ok` 항목 + FAKE_MODE=archive → 성공 판정, `FIXED=1`
- [ ] FAKE_MODE=fail → 원격에 `<stream>-N-agent-failed.md`가 존재하고 그 안에
      `## agent 실패 기록` 섹션과 래퍼명이 있다. `FIXED=0`
- [ ] FAKE_MODE=hang + AUTOQAFIX_IMPL_TIMEOUT=3 → 3초 부근에 실패 처리(위와
      동일 경로), 프로세스 잔류 없음
- [ ] 실패 항목 뒤에도 다음 항목 처리가 계속된다 (fail 항목 1 + archive 항목 1
      → `FIXED=1`, 원격에 `-agent-failed` 1개)
- [ ] 사람 main tree(픽스처의 work/)의 미커밋 더미 파일이 전 과정에서 불변

## 검증

`regression-tests/verify-issue-16.sh` 작성: 위 전부. 실 autotdd 호출 금지
(fake-wrapper의 archive 모드가 성공을 모사).
