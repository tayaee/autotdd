# issue-38: autorevfix → autotddreviewfix 개명 + 위치 인자 문법·인라인 역할 단순화
agent-tier: any

## 배경

autorevfix는 이름이 기억하기 어렵고, 호출 문법이 과하다 — 역할 플래그 4종
(`--model`, `--coder`, `--reviewers`, `--planner`)을 기억해야 하고, coder를
바꾸려면 플래그를 조합해야 한다. grill 세션(2026-07-11)에서 다음이 합의됐다:

- **개명**: `autorevfix` → `autotddreviewfix` ("autotdd 후 review"; 리뷰 결과는
  당연히 고치는 것이므로 fix는 이름에서 생략).
- **역할 단순화**: coder·planner·re-fix는 항상 **실행 세션**(스킬을 호출한
  그 모델·그 대화)이 인라인으로 담당한다. coder를 바꾸는 방법은 플래그가
  아니라 다른 모델의 세션에서 실행하는 것. 리뷰어만 위치 인자로 지정한다.
- **새 문법**: `autotddreviewfix 1 2 3` (셀프 리뷰), `autotddreviewfix 1 2 3
  minimax deepseek` (외부 리뷰어 2), `autotddreviewfix 1 2 3 worktree minimax`
  (worktree 격리 + 리뷰어 1).

조사로 확인된 사실:

- harness-project 래퍼 base는 8종이다: `sonnet minimax qwen gemini fable
  deepseek haiku opus` (현 SKILL.md는 5종만 나열 — 문서 낡음). 스킬이
  base→inner 버전 매핑표를 알 필요는 없다(버전 해석은 래퍼 간접화 몫).
- 전역 스킬은 npx skills의 3겹 구조다: `~/.claude/skills/<이름>`(symlink) →
  `~/.agents/skills/<이름>`(실사본) + `~/.agents/.skill-lock.json`의 키.
- `verify-issue-35.sh`(옛 계약: 플래그 4종·래퍼 10개 나열·name=autorevfix)와
  `verify-issue-36.sh`(옛 planner 출력 경로 단언)는 이번 변경으로 의도적으로
  깨진다 — supersede가 필요하다.

**선행**: 없음. **용어**: CONTEXT.md의 "리뷰 사이클", "셀프 리뷰" 참조
(이번 grill 세션에서 등재).

## 요구사항

1. **개명 (별칭 없음)**: `.claude/skills/autorevfix/` →
   `.claude/skills/autotddreviewfix/`. frontmatter `name`/`description`·트리거
   예시를 새 이름·새 문법으로 갱신. 옛 이름은 리포에서 흔적 없이 제거
   (아카이브 제외).
2. **새 인자 문법 — 위치 인자, 모양으로 분류, 순서 무관**:
   - 정수 토큰 → issue 번호 (1개 이상 필수, 없으면 중단)
   - `worktree` → 격리 키워드
   - 그 외 토큰 → 리뷰어 모델명 (base 이름)
   - 리뷰어명은 `/home/user1/git/harness-project/.local/bin/<name>-cli.sh`
     존재·실행권한으로 **시작 전 일괄 검증**, 하나라도 없으면 전체 중단.
   - 기존 플래그 4종(`--model`, `--coder`, `--reviewers`, `--planner`) 완전
     삭제. 하위 호환 없음.
3. **역할 재정의 (4단계 유지)**:
   - ① coder MVP = 실행 세션이 인라인으로 `/autotdd <N>` 수행
   - ② 리뷰어 = 외부 래퍼 병렬 호출. **미지정 시 셀프 리뷰** — 같은 모델의
     새 컨텍스트 서브에이전트(Agent tool)가 리뷰 파일 작성 (같은 대화에서
     이어서 하는 자기 검토 금지)
   - ③ planner = 실행 세션이 인라인으로 리뷰 파일들을 평가(must-fix /
     good-to-fix / reject 분류), `to-tickets` 스킬로 수정 계획 작성
   - ④ re-fix = 실행 세션이 인라인으로 티켓들을 `/autotdd`로 처리 후 리뷰·
     피드백 md를 aacp 아카이브
4. **worktree 키워드**: ①·④의 `/autotdd` 호출에 `worktree` 키워드로 그대로
   전달. ②·③에는 영향 없음.
5. **파일 네이밍 단순화**:
   - 외부 리뷰어: `issues/issue-N-code-review-by-<base이름>.md` (예:
     `-by-minimax.md`; inner 버전명 사용 중단)
   - 셀프 리뷰: `issues/issue-N-code-review-by-self.md`
   - planner: `issues/issue-N-feedback-review.md` (`-by-*` 접미사 제거 —
     planner는 항상 실행 세션이므로 구분 무의미)
   - 리뷰 프롬프트에 "본문 첫 줄에 자기 모델명(버전 포함)을 기입" 지시를
     포함해 버전 추적성 보존.
6. **실패 정책·멱등성 유지 (파일명만 갱신)**: issue-level fail-fast,
   reviewer continue-with-partial(생존 리뷰만으로 planner 진행 + 누락 고지),
   파일 기반 done-check 전부 유지.
7. **문서 갱신**: `cheatsheet.md`(3곳), `docs/SETUP-autoqafix.md`(1곳) —
   새 이름·새 문법 반영.
8. **회귀 supersede**:
   - `regression-tests/verify-issue-38.sh` 신규 — 새 계약 단언: 새 경로·
     `name: autotddreviewfix`, 옛 플래그 문자열 부재, 위치 인자·worktree·
     `-by-self`·`feedback-review.md` 서술 존재, secrets 부재, 리포 내
     `autorevfix` 문자열 0건(아카이브·과거 verify 주석 제외).
   - `verify-issue-35.sh` 축소 — 여전히 참인 것만: 스킬(새 경로) 존재,
     secrets 부재, 래퍼 디렉토리 존재.
   - `verify-issue-36.sh` 수정 — 옛 출력 경로 단언 제거, to-tickets 사용
     단언은 새 스킬 대상으로 유지.
   - 전체 회귀 green 유지.
9. **companion (harness-project 리포에 커밋)**: 루트에 `clean-skills.sh` +
   `clean-skills.ps1` + `clean-skills.bat`(ps1 호출 얇은 래퍼) 추가.
   - 삭제 목록 하드코딩 배열(leftover 명부의 단일 출처):
     `autorevfix`(autotdd 삭제분), `to-issues`, `to-prd`(mattpocock 1.0→1.1
     삭제분). 향후 스킬 삭제 시 이 배열에 추가.
   - 스킬 이름당 **3겹 제거**: `~/.claude/skills/<이름>`(symlink),
     `~/.agents/skills/<이름>`(실사본), `~/.agents/.skill-lock.json`의 해당
     키. Windows(ps1)는 `%USERPROFILE%` 기준 동일 3겹, lock JSON 편집 포함.
   - 멱등: 없는 항목은 건너뛰고 removed / not present 로그 출력.
   - secrets 불포함(스킬 이름 목록뿐이므로 무관하나 규칙 준수).
10. **아카이브 불가침**: `issues/archive/`의 과거 문서는 수정하지 않는다.
11. **잔여 작업 (리포 밖, 구현 후 별도)**: push 후 npx skills로
    `autotddreviewfix` 전역 설치, `clean-skills.sh` 실행으로 `autorevfix`
    leftover 3겹 제거.

## 승인 기준

- [ ] `.claude/skills/autotddreviewfix/SKILL.md` 존재 + `name: autotddreviewfix`;
      `.claude/skills/autorevfix/` 부재
- [ ] SKILL.md에 `--model`/`--coder`/`--reviewers`/`--planner` 부재; 위치
      인자 분류 규칙·worktree 전달·`-by-self`·`issue-N-feedback-review.md`
      네이밍 서술 존재; secrets 리터럴 부재
- [ ] `grep -rn "autorevfix"` — 아카이브 제외 리포 내 0건
- [ ] `cheatsheet.md`·`docs/SETUP-autoqafix.md`에 새 이름·새 문법 반영
- [ ] harness-project 루트에 `clean-skills.sh`/`.ps1`/`.bat` 존재(실행권한),
      배열에 3항목, 3겹 제거 로직
- [ ] 전체 회귀 PASS (`verify-issue-35.sh`·`verify-issue-36.sh` 수정본 포함)

## 검증

`regression-tests/verify-issue-38.sh` 작성: grep/파일 기반 정적 검사 — 위
승인 기준을 그대로 단언 (issue-31/34/36의 grep 기반 verify와 동일 패턴).
clean-skills는 타 리포이므로 존재·실행권한·배열 3항목 grep 수준으로 검사.

## 구현 결과

- **구현 완료 일시**: 2026-07-12T00:38:00-04:00
- **변경 파일**:
  - `.claude/skills/autotddreviewfix/SKILL.md` (신규)
  - `CONTEXT.md` (수정)
  - `cheatsheet.md` (수정)
  - `docs/SETUP-autoqafix.md` (수정)
  - `regression-tests/verify-issue-35.sh` (수정)
  - `regression-tests/verify-issue-36.sh` (수정)
  - `regression-tests/verify-issue-38.sh` (신규)
  - `harness-project` 리포지토리: `clean-skills.sh`, `clean-skills.ps1`, `clean-skills.bat` 추가 및 커밋 (동반 변경)
- **계획과의 차이**: 없음
- **검증 결과**:
  - `regression-tests/verify-issue-38.sh` 작성 및 실행 성공 (PASS)
  - 전체 회귀 테스트 (`regression-tests/verify-*.sh` 총 35개 스크립트) 실행 성공 (PASS)

