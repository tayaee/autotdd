# issue-35: autorevfix 스킬 추가 — autotdd 측
agent-tier: local-ok

## 배경

harness-project repo에 5 모델 outer/inner `*-cli.sh` 래퍼 + `test-wrappers.sh`
+ ADR 0003이 issue-3 (`d02ccea`)으로 추가됨. 본 이슈는 autotdd repo에
`autorevfix` 스킬을 추가해 그 래퍼들을 오케스트레이션한다.

harness-project 메모리 `secrets-segregation-autotdd-harness-project`에 따라,
secrets는 harness-project에만 둠. autotdd의 SKILL.md는 secrets-free이며 래퍼
경로만 참조한다.

ADR 0003(`~/git/harness-project/docs/adr/0003-autorevfix-wrapper-architecture.md`)에
결정된 설계:

- 명령: `autorevfix <issues...> [--model NAME] [--coder NAME] [--reviewers a,b,c] [--planner NAME]`
- `--model` default: `minimax`. 개별 default 흡수, `--model`이 모든 default 결정
- 이슈별 풀사이클(순차, 리뷰어는 병렬): 코더 MVP → 리뷰어 N → 플래너 → 코더 재수정
- 실패 정책: 이슈 단위 fail-fast, 단계 단위 continue-with-partial
- 멱등성: 출력 파일 존재·비공백으로 done 판정

## 요구사항

1. `.claude/skills/autorevfix/SKILL.md` 작성. 본문은 다음 섹션 포함:
   - `## Argument parsing` — `<issues...>` + 4개 플래그, base-name 의미 명시
   - `## cwd validation` — `.git/` + `issues/issue-N.md` 존재 확인 (autodev/autofix 패턴)
   - `## Per-issue flow` — 4단계(코더 MVP / 리뷰어 N / 플래너 / 코더 재수정),
     각 단계의 prompt 형식과 done 신호 명시
   - `## Failure policy` — 이슈 단위 fail-fast, 단계 단위 continue-with-partial
   - `## Idempotency` — done 신호로 skip, 강제 재실행은 `rm`으로
   - `## Forbidden` — secrets 비저장, done-check 생략 금지, 리뷰어 직렬화 금지
2. `regression-tests/verify-issue-35.sh` 작성. SKILL.md의 정적 계약 검증:
   - 파일 존재 + frontmatter(name, description) 유효
   - 필수 섹션 6개 + 4단계 마커 모두 존재
   - 5 outer + 5 inner wrapper 경로(`-cli.sh`) 10개가 SKILL.md 본문에 등장
   - SKILL.md 본문에 secrets literal(`MINIMAX_API_KEY=...`, `sk-...` 등) 부재
   - `/home/user1/git/harness-project/.local/bin/` 10개 wrapper 모두 실행 가능
3. SKILL.md 본문은 secrets-free. 모든 API 키 / 인증 토큰은 wrapper 안에 있음.
   SKILL.md 본문은 절대경로 참조만 수행.

## 승인 기준

- [ ] `.claude/skills/autorevfix/SKILL.md` 파일 존재 + frontmatter 유효
- [ ] SKILL.md 본문에 6개 필수 섹션 + 4단계 마커 모두 등장
- [ ] SKILL.md 본문이 5 outer + 5 inner wrapper 이름(`*-cli.sh`)을 모두 참조
- [ ] `regression-tests/verify-issue-35.sh` 실행 시 모든 assertion PASS
- [ ] `/home/user1/git/harness-project/.local/bin/` 10 wrapper 모두 실행 가능
- [ ] `grep MINIMAX_API_KEY .claude/skills/autorevfix/SKILL.md` 매치 0건
      (secrets-free 확인)
- [ ] `bash .claude/skills/aacpd/aacp.sh 35 "<summary>"`가 archive + commit +
      push까지 정상 완료

## 검증

`regression-tests/verify-issue-35.sh` (위 grep·파일·실행 가능 검증).

## Blocked by

없음 - 즉시 시작 가능

## 참고

- harness-project commit `d02ccea` (issue-3) — wrappers 10개 + ADR 0003 +
  test-wrappers.sh 추가됨
- 본 repo의 자매 스킬들: `autotdd`, `tdd2`, `aacpd`, `autofix`, `autodev`,
  `autoqa`, `autoqafix` (모두 `.claude/skills/<name>/SKILL.md`)
- 본 스킬은 자매들과 달리 스크립트가 아닌 **순수 트리거** (현재 세션의 Claude가
  4단계를 직접 호출). 모델 호출은 wrapper가 감당하므로 Claude 본 세션은
  orchestrator 역할만.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T20:44:16+0000
- **변경 파일**:
  - `.claude/skills/autorevfix/SKILL.md` (트리거 /autorevfix 신설),
  - `regression-tests/verify-issue-35.sh` (frontmatter·6 섹션·4 단계 마커·10 wrapper 참조·secrets literal 부재·wrapper 실행 가능 검증).
- **계획과 차이**: 없음. SKILL.md 본문은 grill-me로 합의된 12 결정 그대로
  반영 — 인자 파싱(`--model` top-level default = minimax, 개별 default 흡수),
  cwd 검증(autodev 패턴), 4단계 풀사이클(코더 MVP → N 리뷰어 병렬 → 플래너 →
  코더 재수정), 이슈 단위 fail-fast + 단계 단위 continue-with-partial, 출력
  파일 done-check 멱등성. harness-project 결합은 의도된 제약임을 본문에 명시
  (memory `secrets-segregation-autotdd-harness-project` 참조).
- **검증 결과**: verify-issue-35.sh 38 PASS / 0 FAIL. frontmatter·필수 6
  섹션·4 단계 마커·4 플래그·10 wrapper 참조·secrets literal 부재·10 wrapper
  실행 가능 모두 PASS. harness-project 측 test-wrappers.sh도 별도 10/10 PASS.
- **잔여 작업**: `~/.bash_aliases` 갱신(`minimax3='minimax3-cli.sh'` 등 alias
  일관화)은 별도 작업 — 본 사이클에선 SKILL.md만 추가.