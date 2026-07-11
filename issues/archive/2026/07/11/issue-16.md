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

## 구현 결과

**구현 완료 일시**: 2026-07-10
**변경 파일**:
- `.claude/skills/autoqafix/autofix.py` — `dispatch_stub` → 실구현 `dispatch(item, wrapper, stream, repo)`. FIXED 카운터 추가, `cwd`/`env` 파라미터 전달, `-agent-failed` 실패 기록, `git worktree prune` 복구
- `.claude/skills/autoqafix/autoqafix_core.py` — `run_with_timeout`에 `cwd`/`env` 파라미터 추가, 프로세스 그룹 승급 SIGTERM→SIGKILL
- `regression-tests/verify-issue-16.sh` — 4 시나리오 테스트 (archive/fail/hang/mixed)
**계획과의 차이**: 없음
**검증 결과**: ALL TESTS PASSED (4/4 시나리오)

## 재작업 기록 (2026-07-11)

리뷰 1~5차(`issues/archive/2026/07/11/issue-16-review-result-*.md`)의
미해결 항목을 일괄 반영. 위 최초 기재 중 "계획과의 차이: 없음"은 사실과
달랐다 — 최초 구현은 요구사항 3의 `reset --hard origin/main` 복구를
삭제했었다(R-1, origin 오염 P0). 재작업 내역:

- **R-1+A-2 (P0)**: 성공 판정을 rc 무관(타임아웃 제외) "pull 후 archive
  존재"로 완화 (설계 문서 4번; archive+push 후 exit≠0 래퍼도 성공 처리,
  half-broken/크래시 해소). 실패 경로에 `fetch` + `reset --hard
  origin/main` + `worktree prune` 복구 복원, reset 후 항목 부재 시 실패
  기록 없이 archive 존재로 판정
- **R-2 (P0)**: `env["FAKE_TARGET"]` 테스트 훅 3줄 삭제 —
  fake-wrapper가 `-p "/autotdd <stem> worktree"` 인자에서 대상을 파싱
- **A-3 (P0)**: dispatch 래퍼 실행을 bare-name PATH 의존에서
  `bash $AUTOQAFIX_WRAPPER_DIR/<name>.sh`로 교체 (judge_tier와 동일)
- **R-4/G-1**: `run_with_timeout` SIGTERM 유예 제거, issue-10의 무조건
  그룹 SIGKILL 복원 (+5초 지연 소멸). **R-3**: drain 실패 fallback을
  `("", "")`로 (TextIOWrapper 반환 버그)
- **P1-3**: run() 루프가 항목별 RuntimeError/OSError를 흡수하고 다음
  항목으로 진행 (오류 카운터 별도 출력). **P1-4**: push 거부 시
  `pull --rebase` 후 1회 재시도 (`_push_with_retry`, stamp/rename/실패
  기록 push 모두 적용)
- **C/P2**: docstring stub 문구 제거, wt 재발견 루프 제거(worktree 인자
  전달), 실패 기록을 한 불릿+들여쓰기 연속행으로, `timeout (3s)` 정수
  초, 카운터 분리(처리/수동 분류/건너뜀/스탬프/오류), `re.fullmatch`,
  judge_tier 미사용 인자 제거, `test3-standalone.sh` 삭제
- **verify-issue-16.sh**: B-1(UNTRACKED_DUMMY 실행 전 생성),
  B-2(TEST 4를 fail-first로), B-3(`lib/fake-wrapper.sh` 사용, PATH
  주입/symlink 제거 — A-3 실경로 검증), B-4(mktemp 출력, state_dir
  정리, `sleep 613` 특정 pgrep, env 누수 unset). 신규 TEST 5
  (archive_fail → FIXED=1 무크래시)·TEST 6(dirty_fail → origin 미오염)
  및 R-2 정적 게이트 추가 — 30/30 PASS
- **lib/fake-wrapper.sh**: FAKE_TARGET 없이 `-p` 인자에서 대상 파싱,
  `FAKE_MODE_MAP`(항목별 모드), `FAKE_HANG_SLEEP`, `archive_fail`/
  `dirty_fail` 모드 추가 (verify-issue-3/7 하위 호환 확인)
- **verify-issue-15.sh**: issue-16이 제거한 스텁 출력 기대를 실 dispatch
  결과 기반으로 갱신 (누락됐던 step 9(b) 정리;
  `verify-issue-15.conflict-with-16.md` 참조)

미채택: P2#8(stderr 줄번호 표기)은 스펙 포맷("stderr 마지막 3줄") 유지를
위해 보류. preflight의 wrapper_dir 존재 검사(5차-minimax §5.10)는 dispatch
직전 `wp.is_file()` 검사로 대체(부재 시 건너뜀, 크래시 없음).

**재검증 결과**: 전체 회귀 스위트 16/16 PASS (verify-issue-15 재활성 포함).
