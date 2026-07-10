# issue-14: autofix/autodev 1회형 — 디스패처와 실패 처리

## 배경

fix/dev 롤의 진입점. 같은 엔진에 스트림만 다르다. 명세:
`docs/autoqafix-design.md`의 "autofix / autodev" 전체. 이 이슈가 스위트에서 가장
크므로 요구사항 순서대로 함수를 나눠 작게 구현할 것.

## 요구사항

1. `.claude/skills/autoqafix/autofix.py` 작성 (PEP-723). `--stream autofix|issue` 인자
   (기본 autofix). preflight(role은 stream에 따라 fix/dev)·뮤텍스는 issue-13과
   동일 패턴
2. **agent worktree**: `state_dir()/worktree`가 없으면 `git worktree add <경로>
   main`으로 생성, 있으면 `git -C <경로> pull --rebase`. 이후 모든 git 조작·항목
   열거는 이 worktree에서. 사람 main tree는 읽지도 쓰지도 않는다
3. 항목 열거: `issues/<stream>-<N>.md` (접미사 붙은 파일 제외, `## ` 섹션 없는
   예약 중 파일 제외), 번호 오름차순
4. 항목마다:
   ① select-llm 재호출 — none이면 "LLM 부적격, 대기" 출력 후 루프 종료(exit 0)
   ② `agent-tier:` 줄이 없으면(사람 작성): 유료 선정 시에만 래퍼로 tier 판정
   (경량 타임아웃), 스탬프 줄을 파일에 추가·commit·push. 로컬 래퍼만 가능하면
   이 항목은 건너뜀
   ③ tier 매칭: 로컬 래퍼 선정 && tier==paid-only → 건너뜀; tier==manual →
   `-manual` rename·commit·push 후 다음 항목
   ④ 디스패치: worktree에서 `<래퍼> -p "/autotdd <stream>-<N> worktree"` 실행,
   타임아웃 AUTOQAFIX_IMPL_TIMEOUT(기본 10800초)
   ⑤ 성공 판정: worktree에서 pull 후 `issues/<stream>-<N>.md`가 사라지고
   `issues/archive/**/<stream>-<N>.md`가 존재하면 성공
   ⑥ 실패/타임아웃: worktree를 `git -C <wt> reset --hard origin/main`으로 복구,
   `git worktree prune`. 항목 파일에 `## agent 실패 기록` 섹션(없으면 생성) +
   `- <ISO8601> <래퍼>: <exit code 또는 timeout, stderr 마지막 3줄>` 추가 →
   `-agent-failed`로 `git mv` → 그 파일만 commit·push → 다음 항목
5. 처리/건너뜀/실패 건수를 마지막에 요약 출력하고, 완료(archive 이동) 건수를
   exit code가 아닌 stdout 마지막 줄 `FIXED=<n>`으로 보고(autoqafix-loop이 파싱)
6. repo 루트에 `autofix.{sh,ps1,bat}`, `autodev.{sh,ps1,bat}` 런처 (issue-13과
   동일 패턴, autodev는 `--stream issue` 고정)

## 승인 기준

픽스처 + fake-wrapper로:

- [ ] `agent-tier: local-ok` 항목 + FAKE_MODE=archive → 성공 판정, `FIXED=1`
- [ ] FAKE_MODE=fail → 원격에 `<stream>-N-agent-failed.md`가 존재하고 그 안에
      `## agent 실패 기록` 섹션과 래퍼명이 있다. `FIXED=0`
- [ ] FAKE_MODE=hang + AUTOQAFIX_IMPL_TIMEOUT=3 → 3초 부근에 실패 처리(위와 동일
      경로), 프로세스 잔류 없음
- [ ] 스탬프 없는 항목 + tier 판정 fake(TIER: manual) → `-manual`로 rename됨
- [ ] AUTOQAFIX_WRAPPER=qwencli + `agent-tier: paid-only` 항목 → 건너뜀(파일 불변)
- [ ] `-later`/`-manual`/`-agent-failed` 파일은 열거되지 않는다
- [ ] 사람 main tree(픽스처의 work/)에 미커밋 더미 파일을 만들어 둬도 전 과정이
      그 파일을 건드리지 않는다

## 검증

`regression-tests/verify-issue-14.sh` 작성: 위 전부. 실 autotdd 호출 금지
(fake-wrapper의 archive 모드가 성공을 모사).
