# spec: issues/ 파일명 규약 v2

이 문서가 issues/ 파일명 규약의 **단일 정본**이다. `tdd2`·`autotdd`·
`acpd`·`autotddreview`·autoqafix 엔진 등 모든 소비자는 이 규약을 따르며,
각 SKILL.md의 파일명 서술은 이 문서의 요약이다. (issue-39에서 확정,
grill 세션 2026-07-12 합의)

## 문법

```
<스트림>-<번호>[-<슬러그>][__<KEY>-<값>]*.<확장자>
```

한 파일명은 최대 3개 부분으로 구성된다:

| 부분 | 구분자 | 용도 | 독자 |
|---|---|---|---|
| **ID** | — | `issue-127`, `autofix-7` (스트림 + 번호) | 기계 |
| **슬러그** | 앞에 `-` 하나 | 자유 서술 라벨 (`fixing-auth` 등) | 사람 |
| **태그** | 앞에 `__` 둘 | `KEY-값` 쌍, 기계 판정용 | 기계 |

- 스트림: `issue`(사람/파이프라인 등록) / `autofix`(autoqa가 로그에서
  자동 보고). 번호는 스트림별 독립, 재사용 금지(아카이브 포함 최대+1).
- 슬러그: 소문자 kebab, **영문자로 시작**(숫자 시작 금지 — ID 경계의
  시각적 모호 방지). 판정에 일절 관여하지 않는다.
- 태그 KEY는 대문자, 값은 소문자 kebab. KEY 순서는 `TYPE` → `STATE` →
  `BY`로 고정.
- 확장자는 보통 `.md`. 판정 규칙(아래)은 `.md`만 대상이며, `.md` 외
  확장자 산출물도 같은 태그 문법을 쓴다 — 예: 리뷰어·구현자 통계
  `issue-N__TYPE-agent-stats.json`(issue-41/44/45/46 정의, issue-47에서
  단일 파일로 통합). 파이프라인에 중립.

## 태그 3종

| 태그 | 값 | 뜻 |
|---|---|---|
| `__TYPE-` | `code-review` \| `refix-plan` \| `agent-stats` \| (확장 가능) | 산출물 종류 — 작업 아님 |
| `__STATE-` | `later` \| `manual` \| `agent-failed` | 파킹 — 지금 안 함 |
| `__BY-` | 래퍼 base명 (`qwen`, `sonnet`, …) 또는 `self` | 작성자 (code-review에 필수, refix-plan엔 없음). **fixing 파생**에서 복수 작성자는 base명 알파벳 정렬 후 하이픈 연결(`__BY-gemini-qwen-sonnet`). `self`는 예약값으로 다른 리뷰어와 혼합 시 제외되고, self만 있으면 단독(`__BY-self`) |

- `TYPE`은 확장 가능한 enum이다. 새 산출물 종류가 생기면 값만 추가하면
  되고 판정 규칙은 바뀌지 않는다.
- `STATE` 값의 의미: `later`(사람이 미룸) / `manual`(사람 직접 처리) /
  `agent-failed`(에이전트 실패 기록 — 사람이 본문의 실패 기록을 읽고
  보강한 뒤 태그를 제거해 재시도).
- `BY`의 `self`는 **예약값** — 셀프 리뷰(서브에이전트)를 뜻하는 유일한
  비(非)모델명 값. 나머지 값의 도메인은 harness-project 래퍼 base명.

## 판정 규칙 — 단 한 줄

> **TYPE도 STATE도 없으면 pending(작업 큐 대상). 하나라도 있으면 큐에서 제외.**

- `__STATE-*` 파일은 파킹된 **작업**: 사람이 STATE 태그를 지우면(파일명
  rename) pending으로 승격된다. 승격·강등은 항상 "STATE 태그 추가·제거"
  단일 연산.
- `__TYPE-*` 파일은 **산출물**: 영원히 작업이 아니다.
- ID 추출은 정규식 `^(issue|autofix)-([0-9]+)` — 슬러그·태그가 있어도
  번호는 항상 이걸로 뽑는다.
- 번호 해석(`tdd2 127` 등): `issues/issue-127.md`가 있으면 그것,
  없으면 태그 없는 `issues/issue-127-<슬러그>.md` 중 유일한 것.
  태그 없는 후보가 같은 번호에 2개 이상이면 중복 오류로 중단.

## 문법 엄격성 규칙

1. **TYPE⊕STATE 상호 배타**: STATE는 TYPE 없는 파일(작업)에만 허용.
   두 태그의 공존은 문법 위반으로 중단 — 파킹된 산출물은 무의미하다.
2. **슬러그는 영문자로 시작**: `issue-127-3-fix.md` 불허.
3. **KEY는 닫힌 집합**: `TYPE`/`STATE`/`BY`뿐. 미지의 대문자 KEY
   (`__FOO-bar`)는 조용히 pending 처리하지 말고 문법 위반으로 중단.
   소문자 키(`__state-`)도 유효 태그가 아니다 — 문법 위반으로 중단.
   파싱 규칙: KEY는 `__` 뒤 첫 `-`까지, 값 내부의 `-`는 허용
   (`agent-failed`, `code-review`).
4. **`BY-self`는 예약값** (위 태그 표 참조).

## 예약 슬러그 가드 (구 규약 감지)

태그 없는 `.md` 파일이 다음 **구조**에 해당하면 규약 이전(v1) 파일로
간주한다. pending으로 취급하지 말고, "harness-project의
`upgrade-issue-filenames.sh`를 실행하라"는 메시지와 함께 **중단**한다:

- 슬러그가 `later` / `manual` / `agent-failed`와 **정확 일치**
- 파일명이 `-code-review-by-<이름>` / `-feedback-review` /
  `-review-result-<k>-by-<이름>` 구조로 **끝남**

주의: 해당 단어가 슬러그 어딘가에 **포함되는 것만으로는 차단하지 않는다**
— `issue-50-improve-code-review-prompt.md` 같은 정당한 작업
파일명을 금지 어휘로 막지 않기 위해, 매치는 위의 구조(정확·꼬리)로
한정한다. 가드의 목적은 구 파일의 조용한 오분류(파킹 의도 뒤집힘,
리뷰 산출물을 이슈로 구현)를 시끄러운 실패로 바꾸는 것이다.

## 구역·아카이브

- **라이브(issues/)와 아카이브(issues/archive/)는 단일 규약** — 아카이빙
  시 파일명을 변환하지 않고 그대로 `git mv`한다 (`git log --follow`로
  이력 추적 보존).
- **레거시 불변**: 아카이브의 `issue-*-review-result-*-by-*.md` 등 규약
  이전의 역사 기록은 개명·수정하지 않는다.

## 관행 (문법 아님)

- **파생 이슈 슬러그**: 리뷰 must-fix에서 자동 생성되는 이슈는
  `fixing-<원본번호>` — 예: `issue-127-fixing-123.md`는 "127번은 123번의
  리뷰 지적을 고치는 작업". `autofix-` 스트림과의 어휘 혼동을 피하려고
  `autofixing`이 아닌 `fixing`을 쓴다. 정확한 계보(출처 리뷰, finding
  인용)는 파일 본문에 기록한다.

  **finding 슬러그(issue-48)**: agent가 자동 수정하는 티켓(must-fix /
  good-to-fix 모두)에서 "어떤 finding을 고치는지" 파일명만으로 보이게 하기
  위해, 슬러그는 **두 부분**으로 구성될 수 있다 — `fixing-<원본>-<finding-slug>`.
  - `<finding-slug>` 결정 (helper `tools/derive_fixing_slug.py`, 결정적):
    - **자동 추출**: 리뷰 산출물 본문에서 `### Finding: <title>` 헤더 첫 매칭
    - **사람 override**: finding 본문에 `slug: <name>` 헤더 한 줄이 있으면
      자동 추출 대신 그 값을 사용(override 우선)
  - **정규화**: 자동 추출/override 모두 동일 정규화 적용 — lowercase →
    `[^a-z0-9]+` → `-` → 연속 `-` 압축 → 양끝 strip → **50자 truncate**
    (단어 경계에서 자름) → strip. override에도 동일 적용하여 파일명 형식이
    항상 kebab-lowercase로 결정적이 되도록 한다.
  - **슬러그 충돌**: 같은 issue 번호 내에서 동일 슬러그가 두 번 등장하면
    `-2`, `-3`, ... suffix 자동 부여(최대 1000회 시도 후 ValueError).
  - 형식 예: `issue-49-fixing-48-credential-exposure__BY-qwen.md`,
    `issue-50-fixing-48-null-pointer__STATE-later__BY-gemini-qwen-sonnet.md`,
    `issue-51-fixing-48-race-condition__STATE-later__BY-qwen-2.md` (충돌 suffix).

- **finding 슬러그 + 작성 리뷰어 BY**: 모든 fixing 파생 이슈는 finding
  슬러그와 함께 작성 리뷰어 `__BY-<...>` 태그를 가진다. 다중 작성자는
  base명 알파벳 정렬 후 하이픈 연결(`__BY-gemini-qwen-sonnet`).
  `__BY-self`는 예약값(셀프 리뷰)으로, 다른 리뷰어와 혼합 시 제외되며
  self만 있으면 단독(`__BY-self`). 다중 리뷰어 정렬·충돌 suffix는
  helper가 결정성 있게 처리하므로 같은 finding에 대해 항상 같은 파일명.

- **레거시 호환**: 본 PR merge 이전 생성된 archived 파일
  (`issue-127-fixing-123.md`, `issue-127-fixing-123__STATE-later.md`,
  `__TYPE-code-review__BY-qwen.md` 등)은 **개명하지 않는다** (아카이브
  불변 정책). 위 finding 슬러그 + BY 형식은 merge 이후 생성되는 모든 새
  fixing 파생부터 적용한다. 같은 issue 번호(`issue-127-...` 식 ID)에
  구·신 형식 파일이 공존할 수 있으나 ID 추출 정규식이 슬러그·태그를
  무시하므로 pending 판정은 영향받지 않는다.

- 리뷰어의 버전 정보(qwen3.6 등)는 파일명이 아니라 리뷰 파일 **본문 첫
  줄**에 기입한다. 파일명의 `__BY-` 값은 항상 래퍼 base명 — done-check가
  래퍼 이름만으로 결정적이 되도록.

## 예시

```
issue-129.md                              pending
issue-130-fixing-auth.md                  pending + 서술 슬러그
issue-127-fixing-123.md                   pending 파생 (issue-123의 must-fix, v2 이전 형식 — 레거시 불변)
issue-127-fixing-123__STATE-later.md      파킹 파생 (good-to-fix, v2 이전 형식 — 레거시 불변)
issue-9__STATE-manual.md                  파킹: 사람 직접 처리
autofix-8__STATE-agent-failed.md          파킹: 에이전트 실패 기록
issue-21__TYPE-code-review__BY-qwen.md    산출물: qwen의 리뷰
issue-21__TYPE-code-review__BY-self.md    산출물: 셀프 리뷰
issue-21__TYPE-refix-plan.md              산출물: 리뷰 종합 수정계획
issue-21__TYPE-agent-stats.json           산출물: 리뷰어·구현자 통계 (기계용)
# --- issue-48 이후 (merge 이후 생성되는 fixing 파생) ---
issue-49-fixing-48-credential-exposure__BY-qwen.md                       pending 파생 (must-fix, 단일 작성자)
issue-50-fixing-48-null-pointer__STATE-later__BY-gemini-qwen-sonnet.md   파킹 파생 (good-to-fix, 다중 작성자 알파벳 정렬)
issue-51-fixing-48-race-condition__STATE-later__BY-qwen-2.md             파킹 파생 (충돌 suffix -2)
issue-52-fixing-48-mixed-review__BY-qwen.md                              pending 파생 (self+다른 리뷰어 → self 제외, BY 값만)
```

핵심 한 문장: **`__` 뒤는 기계가 읽고(판정), `-` 슬러그는 사람이
읽고(라벨), 본문이 진실을 담는다(계보).**
