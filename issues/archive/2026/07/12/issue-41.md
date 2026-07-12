# issue-41: autotddreview 플래너 이중 게이트 + 파생 이슈 자동 생성·파킹
agent-tier: any

## 배경

grill 세션(2026-07-12) 합의. 현행 Step 3(플래너)은 리뷰 파일들을 종합해
feedback-review.md 하나를 쓰고 Step 4가 must-fix·good-to-fix를 모두 즉시
처리한다. 두 가지를 바꾼다:

1. **선별의 자동화 + 방어선**: 리뷰 finding에 오판이 섞이므로(issue-20:
   27.5%), 검증 안 된 후보가 작업 큐에 직접 들어가면 안 된다. 형식
   게이트와 실질 재검증(내장 /code-review ultra의 검증 패스 차용)을
   플래너에 내장한다.
2. **파생 이슈 파일 생성**: 수정 계획을 별도 계획 문서로만 두지 않고,
   규약 v2 파일명의 파생 이슈로 물화(物化)한다 — 파일명만 보고 어떤
   이슈를 자동 수정하는 작업인지 알 수 있게.

**선행**: issue-39 (파일명 규약 v2), issue-40 (구조화 finding 포맷 —
형식 게이트의 판정 대상).

## 요구사항

autotddreview SKILL.md Step 3·4를 다음으로 재정의한다:

1. **형식 게이트**: 각 리뷰 파일의 finding 중 증거 3요소(파일:라인+인용 /
   실패 시나리오 / 확인 방법)가 하나라도 없는 것은 내용 불문 기계적으로
   `reject` 분류 (사유: "증거 미비"). 근거 제시 책임은 리뷰어에게 있다.
2. **분류**: 게이트 통과 finding을 `must-fix` / `good-to-fix` / `reject`로
   분류 (현행 유지).
3. **실질 재검증 (must-fix 한정)**: must-fix 승격 후보는 플래너가 인용된
   파일:라인을 직접 열어 ① 인용이 실재하고 ② 주장이 성립하는지 확인한
   뒤에만 승격한다. 확인 실패 시 근거를 남기고 reject 또는 good-to-fix로
   강등. (비용 비대칭: must-fix 1건은 무인 /autotdd 풀사이클을 발동하므로
   오판 비용이 재검증 비용보다 압도적으로 크다. good-to-fix는 파킹되어
   사람 눈을 거치므로 재검증 생략.)
4. **파생 이슈 생성**:
   - must-fix → `issues/issue-<신번호>-fixing-<N>.md` (pending)
   - good-to-fix → `issues/issue-<신번호>-fixing-<N>__STATE-later.md`
     (파킹 — 사람이 STATE 태그를 지워 승격할 때까지 파이프라인 제외)
   - 채번: issues/ + issues/archive/ 전체에서 최대 번호 + 1 (번호 재사용
     금지). 생성 직전 기존 번호 재확인.
   - 본문에 계보 필수: 원본 이슈 번호, 출처 리뷰 파일명, 해당 finding
     인용, 재검증 결과. 형식은 to-tickets 스킬 활용.
5. **refix-plan 산출**: `issues/issue-N__TYPE-refix-plan.md`에 전체 판정을
   기록 — 리뷰어별 finding 수, 분류 결과, reject 사유(증거 미비/재검증
   실패 구분), 생성된 파생 이슈 목록. Step 3 done-check는 이 파일 기준.
6. **판정 통계 JSON 누적 (issue-43의 기초 자료)**: refix-plan 작성과
   동시에 같은 판정 데이터를 기계 판독용으로
   `issues/issue-N__TYPE-review-stats.json`에 기록한다.
   - 필수 필드: 이슈 번호, 판정 일시(ISO 8601), 리뷰어별(base 모델명 key)
     `findings`(총 finding 수) / `gate_rejected`(형식 게이트 reject) /
     `verify_rejected`(재검증 실패 reject·강등) / `must_fix` /
     `good_to_fix`, 생성된 파생 이슈 파일명 목록.
   - `.json`은 `.md` 열거에 걸리지 않으므로 파이프라인 판정에 중립.
     사이클마다 1파일이 쌓이는 것이 곧 누적이다 (집계는 issue-43의 CLI
     도구 몫 — 여기서는 기록만).
7. **Step 4 재정의**: `issue-*-fixing-<N>.md` 중 pending인 것들만
   `/autotdd`로 처리 (worktree 키워드 전파 유지). 파킹 파일은 건드리지
   않는다. 완료 후 리뷰 파일들·refix-plan·review-stats JSON을 aacp로
   아카이브 (파일명 그대로, git mv).
8. **실패 정책 유지**: issue-level fail-fast, reviewer
   continue-with-partial, 파일 기반 done-check 멱등성.

## 승인 기준

- [ ] SKILL.md Step 3에 형식 게이트(증거 3요소 미비 → 자동 reject) 서술
- [ ] must-fix 한정 실질 재검증(인용 실재 + 주장 성립 확인) 서술
- [ ] 파생 이슈 파일명 규약(`-fixing-<N>`, good-to-fix는
      `__STATE-later`) + 채번 규칙(아카이브 포함 max+1) 서술
- [ ] 본문 계보 필수 항목 서술
- [ ] `issue-N__TYPE-refix-plan.md` 산출·done-check 서술, `feedback-review`
      문자열 0건
- [ ] `issue-N__TYPE-review-stats.json` 기록 서술 — 필수 필드(리뷰어별
      findings/gate_rejected/verify_rejected/must_fix/good_to_fix) 포함
- [ ] Step 4가 pending 파생 이슈만 처리·파킹 불가침 서술 + 아카이브 대상에
      review-stats JSON 포함
- [ ] 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-41.sh`: SKILL.md grep 정적 검사 — 게이트·
재검증·파생 이슈 파일명·채번·refix-plan 서술 존재, 구 용어 부재 단언.

## 구현 결과

- **구현 완료 일시**: 2026-07-12T17:09:00-04:00
- **변경 파일**:
  - `.claude/skills/autotddreview/SKILL.md` (Step 3을 7단계 절차로 재정의: 수집→형식 게이트→분류→must-fix 재검증→파생 이슈 생성→refix-plan→review-stats JSON; Step 4를 pending 파생 이슈 한정 처리 + 파킹 불가침 + JSON 포함 아카이브로 재정의)
  - `regression-tests/verify-issue-41.sh` (신규)
- **계획과의 차이**: 없음
- **검증 결과**: `verify-issue-41.sh` PASS (게이트·재검증·파생 파일명·채번·계보·refix-plan·JSON 필드 5종·Step 4 규칙·구 용어 부재, 17항목). 전체 회귀 스위트 PASS=38 FAIL=0.
