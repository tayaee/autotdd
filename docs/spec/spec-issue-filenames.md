# spec: issues/ 파일명 규약 v3

이 문서가 issues/ 파일명 규약의 **단일 정본**이다. `tdd2`·`autotdd`·
`aacpd`·`autotddreviewfix`·autoqafix 엔진 등 모든 소비자는 이 규약을 따르며,
각 SKILL.md의 파일명 서술은 이 문서의 요약이다. (issue-39에서 v2 확정,
grill 세션 2026-07-12 합의 / v3는 2026-07-18 세션에서 전면 개정 —
`__TYPE-`/`__STATE-` KEY-값 문법을 폐기하고, 발견용 리터럴 마커로 전환)

## 문법

```
<스트림>-<번호>[-<슬러그>][__<마커>].<확장자>
```

한 파일명은 최대 3개 부분으로 구성된다:

| 부분 | 구분자 | 용도 | 독자 |
|---|---|---|---|
| **ID** | — | `issue-127`, `autofix-7` (스트림 + 번호) | 기계 |
| **슬러그** | 앞에 `-` 하나 | 자유 서술 라벨 (`auth-fix` 등) | 사람 |
| **마커** | 앞에 `__` 둘 | 산출물 종류 / 작업 분류, 기계 판정용 | 기계 |

- 스트림: `issue`(사람/파이프라인 등록) / `autofix`(autoqa가 로그에서
  자동 보고). 번호는 스트림별 독립, 재사용 금지(아카이브 포함 최대+1).
- 슬러그: 소문자 kebab, **영문자로 시작**(숫자 시작 금지 — ID 경계의
  시각적 모호 방지). 판정에 일절 관여하지 않는다.
- 마커는 **닫힌 리터럴 집합**(아래 표) — v2의 `KEY-value` 태그 문법을
  버리고, 문자열 자체가 발견 기준이 되는 리터럴로 바꿨다(v3). 자유 KEY는
  더 이상 없다.
- 확장자는 보통 `.md`. 통계 산출물만 `.json`
  (`issue-<N>__agent-stats.json`). 확장자 앞에 별도 구분자를 두지 않는다
  — 확장자는 언제나 파일명의 마지막 `.` 뒤 그대로.

## 마커 7종 (닫힌 집합)

| 마커 | 형식 | 뜻 | 슬러그 필수? |
|---|---|---|---|
| `code-review-by-<llms>` | `issue-<N>__code-review-by-<llms>.md` | 코드 리뷰 결과 (산출물) | 아니오 |
| `refix-plan` | `issue-<N>__refix-plan.md` | 리뷰 종합 수정계획 (산출물) | 아니오 |
| `agent-stats` | `issue-<N>__agent-stats.json` | 리뷰어·구현자 통계 (산출물, 기계용) | 아니오 |
| `must-fix-by-<llms>` | `issue-<신번호>-<slug>__must-fix-by-<llms>.md` | 필수 수정 파생 이슈 (pending 작업) | 예 |
| `tech-debt-by-<llms>` | `issue-<신번호>-<slug>__tech-debt-by-<llms>.md` | 기술부채 파생 이슈 (파킹, 구 good-to-fix) | 예 |
| `analysis-required` | `issue-<N>-<slug>__analysis-required.md` | 로그 스캔이 자동 등록한 이슈 — 원인 분석·수정 계획이 아직 없는 raw 보고 (`create-tickets.py`) | 예 |
| `STATE-manual` / `STATE-agent-failed` | `issue-<N>__STATE-manual.md` 등 | 범용 파킹(리뷰 무관 — 사람 직접 처리 / 에이전트 실패 기록). 이번 v3 개정 대상 밖, v2 그대로 유지 | 아니오 |

- `<llms>`는 리뷰어 base명(`qwen`, `sonnet`, …) 또는 `self`. 복수 작성자는
  base명 **알파벳 정렬 후 하이픈 연결**(예: `by-gemini-qwen-sonnet`).
  `self`는 예약값 — 다른 리뷰어와 혼합 시 제외되고, self만 있으면
  단독(`by-self`).
- **원본 이슈 번호(계보)는 v3부터 파일명에서 뺀다.** must-fix/tech-debt
  파생 이슈의 원본 이슈 번호·출처 리뷰 파일·finding 인용은 **본문에만**
  기록한다(아래 "관행" 절 참조) — 파일명은 새 이슈 자신의 번호와 슬러그로만
  구성.
- `STATE-manual`/`STATE-agent-failed`는 리뷰 파이프라인과 무관하게 어떤
  원본 이슈든 파킹할 때 쓰는 범용 마커로, v2 문법(`__STATE-<value>`)을
  그대로 유지한다. 이 문서의 v3 개정은 리뷰 산출물·리뷰 파생 이슈 계열
  (`code-review`/`refix-plan`/`agent-stats`/`must-fix`/`tech-debt`)에만
  적용된다.

## 발견 규칙 — 문자열 매치

각 마커는 파일명에 해당 리터럴 문자열이 **부분 문자열로 존재하는지**로
판정한다(정규식 아님, `grep -q`로 충분):

| 발견 키 | 매치되면 |
|---|---|
| `__code-review-by-` | 코드 리뷰 산출물 |
| `__refix-plan` | 수정 계획 산출물 |
| `__agent-stats` | 통계 산출물 |
| `__must-fix-by-` | pending 파생 이슈(즉시 작업 대상) |
| `__tech-debt-by-` | 파킹된 파생 이슈 |
| `__analysis-required` | pending이지만 원인 분석·수정 계획이 없는 raw 보고 — 자동화 시작 전 게이트 대상(아래 "analysis-required 게이트" 절) |
| `__STATE-manual` / `__STATE-agent-failed` | 범용 파킹(v2 유지) |

## 판정 규칙 — 단 한 줄

> **위 발견 키 중 `__must-fix-by-`/`__analysis-required`를 제외한 어느
> 하나라도 매치되면 pending 큐에서 제외. 매치가 없거나
> `__must-fix-by-`/`__analysis-required`만 매치되면 pending(작업 큐
> 대상).**

## analysis-required 게이트

`create-tickets.py`가 로그를 스캔해 자동 생성하는 이슈
(`issue-<N>-<slug>__analysis-required.md`)는 원인 분석도, 수정 계획도
없는 **raw 에러 보고**다 — 사람이나 다른 에이전트가 분석하지 않은 채
`/autotdd`가 그대로 구현을 시도하면 엉뚱한 수정을 밀어붙일 위험이 있다.

그래서 `/autotdd`(및 `/autotddreviewfix`)는 실행 시작 전에
`issues/*__analysis-required*.md`가 하나라도 존재하는지 확인하고, 있으면
`grill-with-docs` 스킬을 먼저 돌려 분석·계획을 채울지 사용자에게 물어야
한다 (각 SKILL.md의 "analysis-required 게이트" 절 참조). 사용자가
거절하면 해당 파일들은 건드리지 않고(스킵) 나머지 정상 pending 이슈만
진행한다.

- `code-review`/`refix-plan`/`agent-stats`는 **산출물** — 영원히 작업이
  아니다.
- `tech-debt`/`STATE-manual`/`STATE-agent-failed`는 **파킹된 작업** —
  사람이 마커 문자열을 파일명에서 제거(rename)하면 pending으로 승격된다.
  예: `issue-50-null-pointer__tech-debt-by-gemini-qwen-sonnet.md` →
  `issue-50-null-pointer.md`.
- `must-fix`는 예외적으로 마커가 있어도 **pending** — 리뷰가 승격시킨
  필수 수정 파생 이슈는 즉시 `/autotdd`가 집어가야 하기 때문(v2의
  "태그 없는 파생 이슈"와 동등한 취급을, v3에서는 명시적 마커로 표현).
- ID 추출은 정규식 `^(issue|autofix)-([0-9]+)` — 슬러그·마커가 있어도
  번호는 항상 이걸로 뽑는다.
- 번호 해석(`tdd2 127` 등): `issues/issue-127.md`가 있으면 그것,
  없으면 마커 없는 `issues/issue-127-<슬러그>.md` 중 유일한 것.
  마커 없는 후보가 같은 번호에 2개 이상이면 중복 오류로 중단.

## 문법 엄격성 규칙

1. **마커는 닫힌 집합**: 위 7종뿐. 미지의 `__<foo>` 마커는 조용히
   pending 처리하지 말고 문법 위반으로 중단.
2. **슬러그는 영문자로 시작**: `issue-127-3-fix.md` 불허.
3. **`must-fix`/`tech-debt`/`analysis-required`는 슬러그 필수**: 마커
   앞에 무엇을 다루는지 보이는 슬러그가 없으면 문법 위반.
4. **`by-self`는 예약값** (위 마커 표 참조).

## 예약 슬러그 가드 (구 규약 감지)

태그 없는 `.md` 파일이 다음 **구조**에 해당하면 규약 이전(v1) 파일로
간주한다. pending으로 취급하지 말고, "harness-project의
`upgrade-issue-filenames.sh`를 실행하라"는 메시지와 함께 **중단**한다:

- 슬러그가 `later` / `manual` / `agent-failed`와 **정확 일치**
- 파일명이 `-code-review-by-<이름>` / `-feedback-review` /
  `-review-result-<k>-by-<이름>` 구조로 **끝남** (단, v3의
  `__code-review-by-<llms>` 마커 자체는 이 가드 대상이 아니다 — `__`
  구분자가 있는 것과 없는 것을 구별한다)

주의: 해당 단어가 슬러그 어딘가에 **포함되는 것만으로는 차단하지 않는다**
— `issue-50-improve-code-review-prompt.md` 같은 정당한 작업
파일명을 금지 어휘로 막지 않기 위해, 매치는 위의 구조(정확·꼬리)로
한정한다. 가드의 목적은 구 파일의 조용한 오분류(파킹 의도 뒤집힘,
리뷰 산출물을 이슈로 구현)를 시끄러운 실패로 바꾸는 것이다.

## 구역·아카이브

- **라이브(issues/)와 아카이브(issues/archive/)는 단일 규약** — 아카이빙
  시 파일명을 변환하지 않고 그대로 `git mv`한다 (`git log --follow`로
  이력 추적 보존).
- **레거시 불변**: 아카이브의 v1(`issue-*-review-result-*-by-*.md`)과
  v2(`issue-*-fixing-*__STATE-later__BY-*.md`,
  `issue-*__TYPE-code-review__BY-*.md`,
  `issue-*__TYPE-refix-plan.md`, `issue-*__TYPE-agent-stats.json` 등)
  역사 기록은 개명·수정하지 않는다. v3 마커 문법은 **본 개정 이후 생성되는
  모든 새 산출물·파생 이슈부터** 적용한다.

## 관행 (문법 아님)

- **파생 이슈 계보**: must-fix/tech-debt 파생 이슈의 본문에는 원본 이슈
  번호, 출처 리뷰 파일명, 해당 finding 인용, 재검증 결과를 **필수**로
  기록한다. v3에서 원본 번호가 파일명에서 빠졌으므로, 이 본문 기록이
  계보를 추적하는 유일한 경로다.
- **finding 슬러그**: agent가 자동 수정하는 티켓(must-fix / tech-debt
  모두)에서 "어떤 finding을 고치는지" 파일명만으로 보이게 하기 위해,
  슬러그는 리뷰 산출물 본문에서 결정적으로 도출된다 (helper
  `tools/derive_fixing_slug.py`):
  - **자동 추출**: 리뷰 산출물 본문에서 `### Finding: <title>` 헤더 첫 매칭
  - **사람 override**: finding 본문에 `slug: <name>` 헤더 한 줄이 있으면
    자동 추출 대신 그 값을 사용(override 우선)
  - **정규화**: 자동 추출/override 모두 동일 정규화 적용 — lowercase →
    `[^a-z0-9]+` → `-` → 연속 `-` 압축 → 양끝 strip → **50자 truncate**
    (단어 경계에서 자름) → strip.
  - **슬러그 충돌**: 같은 issue 번호 내에서 동일 슬러그가 두 번 등장하면
    `-2`, `-3`, ... suffix 자동 부여(최대 1000회 시도 후 ValueError).
- **작성 리뷰어 by**: 모든 파생 이슈는 finding 슬러그와 함께 작성 리뷰어
  `-by-<...>` 를 가진다. 다중 작성자는 base명 알파벳 정렬 후 하이픈
  연결(`-by-gemini-qwen-sonnet`). `-by-self`는 예약값(셀프 리뷰)으로,
  다른 리뷰어와 혼합 시 제외되며 self만 있으면 단독(`-by-self`). 다중
  리뷰어 정렬·충돌 suffix는 helper가 결정성 있게 처리하므로 같은
  finding에 대해 항상 같은 파일명.
- **레거시 호환**: 본 개정 이전 생성된 archived 파일(v1, v2 예시는 위
  "구역·아카이브" 절 참조)은 **개명하지 않는다** (아카이브 불변 정책).
  같은 issue 번호 계열에 신·구 형식 파일이 공존할 수 있으나 ID 추출
  정규식이 슬러그·마커를 무시하므로 pending 판정은 영향받지 않는다.
- 리뷰어의 버전 정보(qwen3.6 등)는 파일명이 아니라 리뷰 파일 **본문 첫
  줄**에 기입한다. 파일명의 `-by-` 값은 항상 래퍼 base명 — done-check가
  래퍼 이름만으로 결정적이 되도록.

## 예시

```
issue-129.md                                              pending
issue-130-auth-fix.md                                     pending + 서술 슬러그
issue-9__STATE-manual.md                                  파킹(v2 유지): 사람 직접 처리
autofix-8__STATE-agent-failed.md                          파킹(v2 유지): 에이전트 실패 기록
issue-21__code-review-by-qwen.md                          산출물: qwen의 리뷰
issue-21__code-review-by-self.md                          산출물: 셀프 리뷰
issue-21__refix-plan.md                                   산출물: 리뷰 종합 수정계획
issue-21__agent-stats.json                                산출물: 리뷰어·구현자 통계 (기계용)
issue-49-credential-exposure__must-fix-by-qwen.md          pending 파생 (must-fix, 단일 작성자)
issue-50-null-pointer__tech-debt-by-gemini-qwen-sonnet.md   파킹 파생 (tech-debt, 다중 작성자 알파벳 정렬)
issue-51-race-condition__must-fix-by-qwen-2.md              pending 파생 (충돌 suffix -2)
issue-52-nullpointerexception-abc.py-12__analysis-required.md  pending (raw 로그 보고, 분석 전 — analysis-required 게이트 대상)
# --- 레거시(불변, 아카이브 전용 — v3 개정 이전 생성분) ---
issue-127-fixing-123.md                                   pending 파생 (v1 형식)
issue-127-fixing-123__STATE-later.md                       파킹 파생 (v2 형식)
issue-49-fixing-48-credential-exposure__BY-qwen.md          pending 파생 (v2 형식)
issue-50-fixing-48-null-pointer__STATE-later__BY-gemini-qwen-sonnet.md  파킹 파생 (v2 형식)
```

핵심 한 문장: **`__` 뒤는 기계가 읽고 발견하며(마커), `-` 슬러그는 사람이
읽고(라벨), 본문이 진실을 담는다(계보).**
