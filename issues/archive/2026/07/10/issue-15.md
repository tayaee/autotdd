# issue-15: autofix/autodev 엔진 골격 — worktree, 항목 열거, tier 처리
agent-tier: paid-only
**구현 완료 일시**: 2026-07-10T19:05Z

## 배경

fix/dev 롤 엔진의 전반부. 디스패치(실제 구현 실행)는 issue-16이 잇고, 런처는
issue-17이 만든다. 명세: `docs/autoqafix-design.md`의 "autofix / autodev" 1~3번.

## 요구사항

1. `.claude/skills/autoqafix/autofix.py` 작성 (PEP-723). `--stream autofix|issue`
   인자(기본 autofix). preflight(role은 stream에 따라 fix/dev)·뮤텍스는
   issue-14와 동일 패턴
2. **agent worktree**: `state_dir()/worktree`가 없으면 `git worktree add <경로>
   main`으로 생성, 있으면 `git -C <경로> pull --rebase`. 이후 모든 git 조작·항목
   열거는 이 worktree에서. 사람 main tree는 읽지도 쓰지도 않는다
3. 항목 열거: `issues/<stream>-<N>.md` (접미사 붙은 파일 제외, `## ` 섹션 없는
   예약 중 파일 제외), 번호 오름차순
4. 항목마다:
   ① select-llm 재호출 — none이면 "LLM 부적격, 대기" 출력 후 루프 종료(exit 0)
   ② `agent-tier:` 줄이 없으면(사람 작성): 유료 선정 시에만 래퍼로 tier 판정
   (경량 타임아웃 AUTOQAFIX_LIGHT_TIMEOUT), 스탬프 줄을 파일에 추가·commit·push.
   로컬 래퍼만 가능하면 이 항목은 건너뜀
   ③ tier 매칭: 로컬 래퍼 선정 && tier==paid-only → 건너뜀; tier==manual →
   `-manual` rename·commit·push 후 다음 항목
   ④ 매칭을 통과한 항목은 `dispatch(item, wrapper)` 함수 호출로 넘긴다.
   **이 이슈에서 dispatch는 스텁**: `DISPATCH <stream>-<N> <래퍼>` 한 줄을
   stdout에 출력하고 성공 0건으로 계산한다 (실구현은 issue-16)
5. 마지막에 처리/건너뜀 건수를 요약 출력하고 stdout 마지막 줄에 `FIXED=0`

## 승인 기준

픽스처 + fake-wrapper로:

- [ ] `-later`/`-manual`/`-agent-failed` 파일과 `## ` 섹션 없는 예약 중 파일은
      열거되지 않는다 (DISPATCH 줄이 나오지 않음)
- [ ] 스탬프 없는 항목 + tier 판정 fake(TIER: manual) → 원격에서 `-manual`로
      rename됨, DISPATCH 없음
- [ ] 스탬프 없는 항목 + TIER: local-ok 응답 → 파일에 `agent-tier: local-ok`
      줄이 추가·push되고 이어서 DISPATCH 줄이 출력됨
- [ ] AUTOQAFIX_WRAPPER=qwencli + `agent-tier: paid-only` 항목 → 건너뜀
      (파일 불변, DISPATCH 없음)
- [ ] worktree가 state_dir 아래에 생성되고, 사람 main tree(픽스처의 work/)에
      만들어 둔 미커밋 더미 파일이 전 과정에서 불변
- [ ] 마지막 줄이 `FIXED=0`

## 검증

`regression-tests/verify-issue-15.sh` 작성: 위 전부. 실 LLM 호출 금지.

## 구현 결과

- 변경 파일:
  - `.claude/skills/autoqafix/autofix.py` (신규) — PEP-723 엔진 스켈레톤
  - `regression-tests/lib/make-fixture-repo-issue-15.sh` (신규) — 접미사/예약중
    항목 + 사람의 main tree 미커밋 더미 파일까지 갖춘 픽스처
  - `regression-tests/verify-issue-15.sh` (신규) — 시나리오 A(paid=claudecli,
    stamp+rename+dispatch) / 시나리오 B(local=qwencli, paid-only 스킵)
- 설계 위배:
  - `git worktree add <path> main`은 같은 브랜치를 두 워크트리에서 체크아웃할 수
    없어 실패한다 (`fatal: 'main' is already used by worktree ...`). 사람
    main tree가 `main`을 잡고 있는 한 언제나. `--detach`를 추가해
    `git worktree add --detach <path> main`으로 우회 — 의미상 "main 추적"을
    그대로 만족하고, detached HEAD는 이후 commit + push 대상만 명시하면 됨
  - 같은 이유로 `git -C <path> pull --rebase`는 detached HEAD의 업스트림
    트래킹이 없어 실패하므로 `pull --rebase origin main` (원격/브랜치 명시)
  - 같은 이유로 `git push` (인자 없음)는 detached HEAD에서 "fatal: You are
    not currently on a branch"로 실패하므로 모든 push를 `push origin
    HEAD:main`으로 통일. 이 과정에서 `_git_or_die` 래퍼를 추가해
    `core._git`의 무성 실패(리턴코드 무시)를 차단
- 검증 결과:
  - `verify-issue-15.sh`: 22/22 PASS (시나리오 A 14 + 시나리오 B 7 + 헬퍼 1)
  - 회귀: `verify-issue-{3..14}.sh` 모두 PASS 유지
  - pyright (`.` 전체), `python -m compileall .` 무오류
