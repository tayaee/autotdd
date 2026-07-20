# issue-39: 파일명 규약 v2 전면 교체 — `__TYPE/__STATE/__BY` 대문자 태그 문법
agent-tier: any

## 배경

grill 세션(2026-07-12)에서 issues/ 파일명 규약 v2가 확정됐다. 동기: 완전
무인 파이프라인에서 파일명은 사실상 프로토콜인데, 현행 규약은 "숫자 뒤에
뭐가 붙으면 작업 아님"이라는 암묵 규칙에 의존하고, 파킹 접미사(`-later` 등)
와 리뷰 산출물(`-code-review-by-*`)이 문법상 구분되지 않으며, 시간이 지나면
몇 종류의 규약이 존재하는지 파일명만으로 파악할 수 없다.

**확정된 문법**: `<stream>-<N>[-<slug>][__<KEY>-<value>]*.md`

- KEY는 대문자 3종, 이 순서 고정: `TYPE` → `STATE` → `BY`. 값은 소문자 kebab.
- `TYPE`: `code-review` | `refix-plan` — 산출물 (작업 아님)
- `STATE`: `later` | `manual` | `agent-failed` — 파킹 (지금 안 함)
- `BY`: base 모델명 (`qwen`, `sonnet`, `self` 등) — code-review 필수,
  refix-plan 생략 (플래너는 항상 실행 세션이라 무기명)
- **판정 규칙 (단일)**: TYPE도 STATE도 없으면 pending(작업 큐 대상).
  하나라도 있으면 큐 제외. 슬러그는 판정에 불관여하는 사람용 라벨.
- 슬러그 관행: 파생 이슈는 `fixing-<원본번호>` (`autofix-` 스트림과의
  어휘 혼동을 피하기 위해 `autofixing` 아닌 `fixing`). 정확한 계보는 본문에.
- 라이브·아카이브 **단일 규약** — 아카이빙 시 파일명 변환 없음.
- 레거시 `issue-*-review-result-*-by-*.md`(아카이브)만 역사 기록으로 불변.

예시:

```
issue-129.md                              pending
issue-130-fixing-auth.md                  pending + 서술 슬러그
issue-127-fixing-123.md                   pending 파생 (must-fix)
issue-127-fixing-123__STATE-later.md      파킹 파생 (good-to-fix, 승격=태그 제거)
issue-9__STATE-manual.md                  파킹: 사람 손 필요
issue-21__TYPE-code-review__BY-qwen.md    산출물: qwen의 리뷰
issue-21__TYPE-refix-plan.md              산출물: 리뷰 종합 수정계획
```

**예약 슬러그 가드**: 태그 없는 파일이 다음 **구조**에 해당하면 구(舊)
규약 파일로 간주 — pending 취급하지 말고 "upgrade-issue-filenames.sh를
실행하라"는 메시지와 함께 중단한다:

- 슬러그가 `later`/`manual`/`agent-failed`와 정확 일치
- 파일명이 `-code-review-by-<이름>` / `-feedback-review` /
  `-review-result-<k>-by-<이름>` 구조로 끝남

주의: 슬러그 어딘가에 해당 단어가 **포함**되는 것만으로는 차단하지 않는다
— `issue-50-improve-code-review-prompt.md` 같은 정당한 작업 파일명을
금지 어휘로 막지 않기 위해 구조(꼬리) 매치로 한정한다. 가드의 목적은
구 파일의 조용한 오분류(파킹 의도 뒤집힘, 리뷰 파일을 이슈로 구현)를
시끄러운 실패로 바꾸는 것.

마이그레이션 도구는 이미 존재한다:
`/home/user1/git/harness-project/upgrade-issue-filenames.sh`
(--dry-run 지원, 멱등, git mv/add 포함, 픽스처 검증 완료).

**선행**: 없음. 이 이슈가 issue-40/41/42의 선행이다.
**supersede**: issue-38 §5의 파일 네이밍(`issue-N-code-review-by-<base>.md`,
`issue-N-feedback-review.md`)을 본 규약이 대체한다.

## 요구사항

1. **spec 문서 신설**: `docs/spec/spec-issue-filenames.md` — 위 문법·태그
   3종·판정 규칙·예약 슬러그 가드·예시표·레거시 불변 규칙·슬러그 관행을
   명문화. 이 문서가 규약의 단일 정본이며 각 SKILL.md는 이를 따른다고 명기.
   TYPE 값은 확장 가능한 enum이고 `.md` 외 확장자 산출물도 같은 태그
   문법을 쓴다고 명기 (예: issue-41이 정의하는
   `issue-N__TYPE-review-stats.json` — 판정 규칙은 `.md`만 대상이므로
   파이프라인에 중립). **문법 엄격성 규칙 4건**도 포함:
   - **TYPE⊕STATE 상호 배타**: STATE는 TYPE 없는 파일(작업)에만 허용.
     공존은 문법 위반으로 중단 (파킹된 산출물은 무의미).
   - **슬러그는 영문자로 시작**: 숫자 시작 금지 — ID 경계의 시각적 모호
     방지 (`issue-127-3-fix.md` 불허).
   - **KEY는 닫힌 집합**: `TYPE`/`STATE`/`BY`뿐. 미지의 대문자 KEY
     (`__FOO-bar`)는 조용히 pending 처리하지 말고 문법 위반으로 중단.
     파싱 규칙 명기: KEY는 `__` 뒤 첫 `-`까지, value 내부의 `-`는 허용.
   - **`BY-self`는 예약값**: BY 도메인은 래퍼 base명이며 `self`(셀프
     리뷰)만 역할명 예약값.
2. **tdd2 SKILL.md**: Stream conventions 절 교체 — 열거는 정규식
   `^(issue|autofix)-([0-9]+)`로 ID 추출, pending 판정은 "TYPE/STATE 태그
   부재", 구 접미사(-later/-manual/-agent-failed) 서술 삭제, 예약 슬러그
   가드 서술 추가. bash 열거 루프 예시도 새 규칙으로 갱신.
3. **autotdd SKILL.md**: 동일 갱신 (열거 루프, done-check grep 대상 경로가
   슬러그 있는 파일에도 동작하도록).
4. **autotddreviewfix SKILL.md**: 리뷰 파일명 `issue-N__TYPE-code-review__BY-<base>.md`
   (셀프 리뷰는 `__BY-self`), 플래너 산출 `issue-N__TYPE-refix-plan.md`
   (feedback-review.md 대체), Step 2~4 done-check·아카이브 glob을 새
   파일명으로 갱신.
5. **aacpd SKILL.md**: 파일명 서술 갱신 + 아카이빙은 파일명 그대로 `git mv`
   사용 명기 (이력 추적 `git log --follow` 보존).
6. **autoqafix 실행 코드**: `error-to-autofix.py`, `autofix.py`의
   구 접미사 생성·판정 로직을 `__STATE-agent-failed` 등 태그로 교체.
7. **문서 갱신**: `docs/SETUP-autoqafix.md`, `docs/autoqafix-design.md`의
   구 접미사 서술 갱신.
8. **회귀 supersede**: 구 접미사를 단언하는 기존 verify 스크립트 수정,
   `regression-tests/verify-issue-39.sh` 신규 (승인 기준 단언), 전체 green.
9. **아카이브 불가침**: `issues/archive/` 과거 문서의 본문은 수정하지
   않는다. 파일명 개명이 필요한 경우 upgrade 스크립트 실행으로만 (현재
   이 리포 라이브 issues/에 구 규약 대상 파일은 0건).

## 승인 기준

- [ ] `docs/spec/spec-issue-filenames.md` 존재 — 문법·3태그·판정 규칙·가드·
      예시 포함
- [ ] tdd2/autotdd/aacpd/autotddreviewfix SKILL.md에서 아카이브 인용 제외
      `-later.md`/`-manual.md`/`-agent-failed.md`/`feedback-review.md`/
      `code-review-by-` 구 문자열 0건
- [ ] 위 4개 SKILL.md에 `__TYPE-`/`__STATE-`/`__BY-` 서술 존재
- [ ] `error-to-autofix.py`·`autofix.py`에 `__STATE-` 태그 로직 존재, 구
      접미사 로직 부재
- [ ] 예약 슬러그 가드가 tdd2·autotdd SKILL.md에 서술됨 (upgrade 스크립트
      안내 문구 포함, 구조 매치 한정 — 포함 매치 금지 명기)
- [ ] spec 문서에 문법 엄격성 규칙 4건(TYPE⊕STATE 배타, 슬러그 영문자
      시작, 닫힌 KEY 집합, BY-self 예약값) 존재
- [ ] 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-39.sh`: grep/파일 기반 정적 검사 — 위 승인
기준을 그대로 단언 (issue-38의 grep 기반 verify와 동일 패턴). 파이썬 2건은
구 접미사 문자열 부재 + 새 태그 문자열 존재 grep 수준.

## 구현 결과

- **구현 완료 일시**: 2026-07-12T16:56:30-04:00
- **변경 파일**:
  - `docs/spec/spec-issue-filenames.md` (신규 — 규약 v2 단일 정본)
  - `.claude/skills/tdd2/SKILL.md` (Stream conventions·Argument parsing·열거 루프 v2 교체)
  - `.claude/skills/autotdd/SKILL.md` (Stream conventions·목록·상태 확인 v2 교체)
  - `.claude/skills/aacpd/SKILL.md` (아카이브 단일 규약+git mv 명기, pending 판정 v2)
  - `.claude/skills/autotddreviewfix/SKILL.md` (리뷰 산출물 `__TYPE-code-review__BY-*`/`__TYPE-refix-plan`, done-check·아카이브 glob 갱신)
  - `.claude/skills/autoqafix/autofix.py` (STATE 태그 열거·rename, LegacyFilenameError 가드)
  - `.claude/skills/autoqafix/error-to-autofix.py` (`__STATE-manual` rename·커밋 접두사)
  - `docs/SETUP-autoqafix.md`, `docs/autoqafix-design.md` (상태 태그 서술)
  - `regression-tests/verify-issue-39.sh` (신규)
  - `regression-tests/verify-issue-{13,15,16,22,38}.sh` + `lib/make-fixture-repo-issue-15.sh` (v2 supersede) + `verify-issue-{13,15,16,22,38}.conflict-with-39.md` (충돌 기록 5건)
- **계획과의 차이**: 두 가지. ① 요구사항 8의 supersede 대상에 verify-issue-38도 포함됨(`-by-self`/`feedback-review.md`를 단언하고 있었음 — 계획 수립 시점엔 38이 최신이라 목록에 명시되지 않았음). ② autofix.py의 가드는 SKILL.md 서술을 넘어 실행 코드로 구현(LegacyFilenameError — 구 규약 파일 감지 시 upgrade-issue-filenames.sh 안내 후 중단). aacp.sh의 슬러그 파일 해석은 이번 범위에 포함하지 않음 — 파생 이슈를 소비하는 issue-41에서 처리 예정.
- **검증 결과**: `verify-issue-39.sh` PASS (스펙 16항목 + SKILL.md 신규 문법·구 문자열 0건 + 파이썬 태그 로직·py_compile + docs 갱신). 전체 회귀 스위트 PASS=36 FAIL=0 (supersede된 13/15/16/22/38의 behavioral 테스트가 신규약 동작을 실제 픽스처로 재검증).
