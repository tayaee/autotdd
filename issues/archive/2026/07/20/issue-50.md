# issue-50: agent-stats.json cost_details — mvp/review/refix-plan/refix 4단계 5h/7d 쿼터 계측 (issue-49 재도입, 모델명 파라미터화)
agent-tier: any

## 배경

grill 세션(2026-07-20, llmserver-project) 합의. `/autotdd`(tdd2 단독)만
반복 실행할 때 `cost_details`가 전혀 생기지 않는다는 사용자 지적에서
출발 — 조사 결과 tdd2/autotddreview/acpd 어디에도 쿼터 계측 훅이 없었다.

**issue-49(2026-07-13)가 정확히 이 기능을 이미 구현했었다**
(`7eae435`, `811c5d2`) **— 그러나 같은 날 저녁 전면 리버트됐다**
(`d512b8e`, 20:34). 리버트 커밋 메시지는 "미완 상태로 남아있던 정리를
완료"라고만 되어 있고, 리버트를 **왜** 결정했는지(설계 결함/버그/단순
보류)는 커밋 로그 어디에도 없다 — 사용자 본인도 사유를 기억하지
못한다. `issue-49.md`는 archive에 "구현 완료"로 남아 실제 코드 상태와
불일치한 채 방치돼 있다(이번 이슈로 정정하지 않음 — 별개 정리 대상).

**이번 grill에서 issue-49 설계 대비 바뀐 점은 단 하나**: issue-49는
Step1(mvp)/Step3(planner)/Step4(refix)의 "오케스트레이터 자신의
base명"을 SKILL.md 프로즈에 `sonnet` 등으로 사실상 하드코딩 전제하고
있었다. 이 스킬 세트는 여러 AI CLI 도구(Claude/Codex/Gemini 등)에서
쓰일 수 있다는 전제(`CLAUDE.md` 상단 "Shared skills ... apply to all AI
CLI tools")와 맞지 않는다는 지적이 나와, **오케스트레이터 자신의
model 식별자를 매 호출 시점에 실행 세션이 파라미터로 결정해 넘기는
형태로 일반화**하기로 했다. 그 외 스키마·훅 위치·설계는 issue-49와
동일하다.

## 요구사항

### 0. 모델명 정확성 — 결정 방식보다 우선하는 제약

`<base명>`을 **어떤 방식으로 결정하든 상관없다** (이슈 파일 프로즈에
지시문으로 박아넣든, `coders.<base명>` 키 재사용이든, 실행 세션이
스스로 판단하든) — 단, **기록되는 값이 실제로 그 단계를 수행한 세션의
모델과 정확히 일치해야 한다**는 것만은 타협 불가다. 틀린 모델명으로
기록된 `cost_details`는 없는 것보다 나쁘다 — 존재하지 않는 액션의
쿼터 소모로 잘못 집계되어 이후 스코어보드/의사결정을 오염시킨다.

이 요구사항은 4번(tdd2)·5번(autotddreview) 항목의 "실행 세션 자신의
model 식별자" 지칭 전체에 적용된다:

- `coders.<base명>` 키를 재사용하는 지점(Step 5/11, Step 2 self-review,
  Step 3, Step 4)은 **그 키가 애초에 정확히 채워졌다는 전제**에
  의존한다 — Step 1(tdd2 Step 5)에서 최초로 그 값을 채우는 지점이
  가장 중요한 검증 지점이다.
- 값이 불확실하거나 판단할 수 없는 상황이 되면 **추측해서 아무 base명이나
  채우지 말 것** — 침묵도 추측도 금지. 이런 경우 `description`에 그
  사실을 명시하고 `model` 필드 자체를 확인 가능한 값(예: 세션이 실제로
  보고한 값)으로만 채운다. "모델을 특정할 수 없으면 항목 자체를
  건너뛴다" 같은 예외 처리는 이번 이슈 스코프에서 정하지 않으므로,
  구현 중 이 상황이 실제로 발생하면 구현을 멈추고 사용자에게 확인한다.

### 1. 공통 라이브러리 `tools/cost_entry.py` (issue-49와 동일)

- Pydantic 모델 `CostDetailEntry`: `ts`(ISO8601) / `model`(base명) /
  `five_hour_used_pct`(float|None) / `seven_day_used_pct`(float|None) /
  `description`(str).
- `find_stats_file(repo, target)` — `issues/<stream>-<N>__TYPE-agent-stats.json`
  경로 결정(`agent-stats-archive.py`와 동일한 `issue|autofix` 정규식).
- `append_cost_detail(...)` — 대상 파일의 `cost_details` 배열에 append.
  `dryrun=True`면 파일 존재 여부와 무관하게 (경로, entry)만 계산해 반환
  (issue-49에서 사용자가 실제로 재현·보고했던 "dryrun인데 파일 없음
  에러" 버그를 처음부터 피하도록, dryrun 분기를 파일 조회보다 **먼저**
  둔다).
- `query_check_usage_pct(provider_key)` — `~/.claude/plugins/cache/claude-dashboard/claude-dashboard/*/dist/check-usage.js --json`
  호출해 `provider_key`(`claude`/`gemini`)의 `fiveHourPercent`/
  `sevenDayPercent`를 얻는다. 조회 실패는 `(None, None)` + stderr 경고
  (침묵 금지).

### 2. base명별 스크립트 8개 — `tools/log-cost-<base>.py`

`sonnet`/`opus`/`haiku`/`fable`/`gemini`/`minimax`/`qwen`/`deepseek`.

- CLI: `log-cost-<base>.py [--dryrun] <repo-path> <issue-N|autofix-N> "<description>"`.
- `sonnet`/`opus`/`haiku`/`fable` → `query_check_usage_pct("claude")`.
- `gemini` → `query_check_usage_pct("gemini")`.
- `minimax`/`qwen`/`deepseek` → 조회 수단 없음, `five_hour_used_pct`/
  `seven_day_used_pct`를 `None`으로 기록(미지원 provider임을 출력
  메시지에 명시 — 침묵 금지).
- 전부 PEP723 인라인 의존성(`dependencies = ["pydantic"]`) + 얇은
  `.sh`/`.bat`/`.ps1` `uv run` wrapper 동반(issue-49에서 이미 확인된
  필요사항 — pydantic 의존성 때문에 맨 `python3` 직접 호출은
  `ModuleNotFoundError`가 난다. SKILL.md는 항상 `.sh`/`.bat`/`.ps1`
  wrapper만 호출하고 맨 `.py`를 직접 호출하지 않는다).

### 3. `tools/log-cost-summary.py` (issue-49와 동일)

- CLI: `log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>`.
- `cost_details`를 모델별로 그룹화해 `five_hour_sum`/`seven_day_sum`
  계산(`null`은 합산 제외, 전부 `null`이면 결과도 `null`).
- `cost_summary` 필드에 기록.

### 4. `tdd2/SKILL.md` — mvp 전후 계측, **모델명 파라미터화**

- Step 5(agent-stats.json 최초 생성 직후): "before mvp" 이벤트 기록.
  `tools/log-cost-<base명>.sh <repo-path> issue-<N> "before mvp"` —
  `<base명>`은 **이 tdd2 인스턴스를 실행 중인 세션 자신의 model
  식별자**(`sonnet`/`opus`/`gemini`/... 중 하나)이며, Step 5 시작
  시점에 실행 세션이 스스로 판단해 채워 넣는 값이지 SKILL.md에
  하드코딩된 이름이 아니다. `coders.<base명>` 키(Step 5/11이 만드는
  agent-stats.json의 coder 키)와 동일한 값을 재사용한다 — 이미 그
  세션의 model 식별자를 알아야 채울 수 있는 필드이므로 별도 판단
  로직을 새로 만들 필요는 없다.
- Step 11(`coders.<base명>.mvp` 채움 직후): "after mvp" 이벤트, 같은
  `<base명>` 사용.

### 5. `autotddreview/SKILL.md` — review/refix-plan/refix 전후 계측, **모델명 파라미터화**

- **Step 2(Reviewers)**: 리뷰어별 개별 before/after 쌍.
  - External reviewer `<X>`: `<X>` 자신이 곧 model 식별자이므로
    `tools/log-cost-<X>.sh`를 그대로 쓴다(파라미터화 대상 아님 — 이미
    명시적).
  - Self-review: `tools/log-cost-<base명>.sh ... "before review"` /
    `"after review"` — `<base명>`은 **오케스트레이팅 세션 자신의 model
    식별자**(Step 1에서 이미 확정된 coder base명과 동일 값 재사용).
- **Step 3(Planner)**: 시작 직후 "before refix-plan", `review_outcome`
  병합 직후 "after refix-plan" — 둘 다 `<base명>` = 오케스트레이팅
  세션 자신의 model 식별자(Step 1/Step 2 self-review와 동일 값).
- **Step 4(Coder re-fix)**: 파생 이슈 처리 시작 전 "before refix",
  전부 끝난 직후 "after refix" — 파생 이슈 개수와 무관하게 **원본
  이슈에 한 쌍만**. `<base명>` = 이 이슈의 `agent-stats.json`의
  `coders` 키(Step 1의 coder와 동일 값, 재조회 없이 그대로 재사용).

일관된 원칙: **"오케스트레이팅 세션 자신의 model 식별자"는 매번 새로
판단하지 않는다** — 그 이슈의 Step 1(tdd2 Step 5)에서 이미 한 번
확정된 값을 `coders.<base명>` 키로 그대로 재사용한다. SKILL.md
프로즈는 특정 모델명을 절대 하드코딩하지 않고 "실행 세션 자신의 model
식별자"라고만 지칭한다.

### 6. `acpd/aacp.sh` / `aacp.ps1` — cost_summary 계산 훅 (issue-49와 동일)

- `issue-N__TYPE-agent-stats.json`을 archive로 `git mv`하기 직전,
  기존 `agent-stats-archive.py` 호출 **바로 앞**에
  `uv run tools/log-cost-summary.py "$REPO_ROOT" "${STREAM}-${N}"` 추가.
- `tools/log-cost-summary.py`가 없는 대상 repo(샌드박스 테스트 등)에서
  깨지지 않도록 "있으면 실행, 없으면 스킵" 방식(`deploy.sh`와 동일
  패턴)으로 존재 확인 후 호출.
- `acpd/SKILL.md` 문서 갱신.

### 7. 하지 말 것

- `coders`/`reviewers`/`derived_by_reviewers` 등 기존 agent-stats.json
  필드의 의미·형식 변경.
- minimax/qwen/deepseek용 대체 사용량 조회 수단을 새로 만들기(범위
  밖 — null 기록으로 충분, issue-49와 동일 결정 유지).
- `issue-49.md`(archive)의 "구현 완료" 기록을 이번 이슈에서 정정하는
  것 — 별개 정리 대상, 이번 스코프 아님.
- reviewer-scoreboard.py 등 다른 도구의 집계 로직 변경.

## 승인 기준

- [ ] `tools/cost_entry.py` 신규: `CostDetailEntry` + `append_cost_detail`
      (dryrun이 파일 부재에도 에러 없이 동작) + `query_check_usage_pct`.
- [ ] `tools/log-cost-{sonnet,opus,haiku,fable,gemini,minimax,qwen,deepseek}.py`
      8개 + 각각의 `.sh`/`.bat`/`.ps1` uv wrapper, `--dryrun` 지원.
- [ ] `tools/log-cost-summary.py` 신규 + wrapper 3종, `cost_summary` 계산.
- [ ] `tdd2/SKILL.md`: Step 5/11에 before/after mvp 계측 지시 —
      **model 식별자가 하드코딩이 아니라 "실행 세션 자신의 값"으로
      명시**돼 있음.
- [ ] `autotddreview/SKILL.md`: Step 2(리뷰어별, self-review는 세션
      자신의 값)/Step 3/Step 4(원본 이슈에 한 쌍만)에 계측 지시 존재,
      전부 model 식별자 하드코딩 없이 파라미터로 지칭.
- [ ] `acpd/aacp.sh`·`aacp.ps1`: `agent-stats-archive.py` 호출 직전
      `log-cost-summary.py` 존재 확인 후 호출. `acpd/SKILL.md` 동기화.
- [ ] `regression-tests/verify-issue-50.sh`: 9개 스크립트(.py/.sh/.bat/.ps1)
      존재 확인 + SKILL.md가 `.sh` wrapper만 호출(맨 `.py` 직접 호출
      0건)하는지 grep 단언 + 스크래치 픽스처로 실제 append/summary/
      dryrun 동작 검증 + `aacp.sh` 전체 훅 흐름 시뮬레이션.
- [ ] 모델명 정확성: `coders.<base명>` 키를 재사용하는 모든 계측
      지점(Step 5/11, Step 2 self-review, Step 3, Step 4)에서 그
      값이 실제 실행 세션의 model과 다를 수 있는 경로(worktree 모드,
      재개/resume 케이스 등)를 규정서가 명시적으로 다뤘는지 확인.

## 검증

`bash regression-tests/verify-issue-50.sh`:
- 스크래치 `issues/issue-<N>__TYPE-agent-stats.json` 픽스처에
  `log-cost-sonnet.sh`(실측) + `log-cost-minimax.sh`(null) 호출 →
  `cost_details`에 정확한 항목 append.
- `--dryrun` 호출은 파일을 변경하지 않고, 파일이 없어도 에러 없이
  entry JSON을 출력.
- `log-cost-summary.sh` 호출 후 `cost_summary`가 모델별로 정확히
  합산(null 제외, 전부 null이면 결과도 null).
- 임시 git repo에서 `aacp.sh`를 끝까지 실행해 `cost_summary`가
  `archived`/`duration`과 함께 최종 아카이브 파일에 존재.
- `tdd2`/`autotddreview`/`acpd` SKILL.md에 관련 지시 존재 + model
  식별자 하드코딩(`sonnet` 등 리터럴이 지시문 안에 고정 값으로 박혀
  있는지) 없음을 grep으로 단언.

## 구현 결과

**구현 완료 일시**: 2026-07-20T16:45:00-04:00

**변경 파일**:
- `tools/cost_entry.py` — 신규. `CostDetailEntry`(Pydantic), `append_cost_detail`
  (dryrun이 파일 부재에도 에러 없이 동작), `query_check_usage_pct`. issue-49
  리버트 전 커밋(`811c5d2`)에서 복원 후 두 가지 수정: (1) 파일 경로를
  `__TYPE-agent-stats.json` → `__agent-stats.json`으로 교정(이슈 파일명
  규약이 v3로 개정되며 `TYPE-` 접두사가 제거된 것을 리버트 이후 몰랐던
  코드), (2) 타임스탬프를 UTC `Z` → 로컬 오프셋 ISO8601로 교정(리버트
  이후 별도 커밋 "Use local timezone for the fields in agent-stats.json"로
  전체 스키마 규약이 바뀐 것을 반영).
- `tools/log-cost-{sonnet,opus,haiku,fable,gemini,minimax,qwen,deepseek,summary}.py`
  9개 + `.sh`/`.bat`/`.ps1` uv wrapper 27개 — 동일 커밋에서 복원, 수정
  불필요(각 스크립트는 `cost_entry`/자체 로컬 `find_stats_file` 경유라
  위 경로 수정이 자동 반영됨).
- `skills/tdd2/SKILL.md` — Step 5(agent-stats.json 최초 생성 직후)에
  "before mvp", Step 11(`coders.<base명>.mvp` 채움 직후)에 "after mvp"
  계측 지시 추가. `<base명>`을 특정 모델명으로 하드코딩하지 않고 "바로
  위 `coders`에 쓴 것과 정확히 동일한 값"으로 지칭(오늘 grill에서 확정한
  일반화) + 값이 불확실하면 추측하지 말고 멈추라는 경고 추가.
- `skills/autotddreview/SKILL.md` — Step 2(리뷰어별 개별 before/after,
  self-review는 세션 자신의 base명), Step 3(before/after refix-plan),
  Step 4(파생 이슈 전체를 감싸는 한 쌍만, before/after refix) 계측 지시
  추가. 전부 "정확히 같은 값을 재사용"을 명시해 모델명 하드코딩을
  금지.
- `skills/acpd/aacp.sh` / `aacp.ps1` — `agent-stats-archive.py` 호출
  직전, 대상 repo에 `tools/log-cost-summary.py`가 있으면(없으면 스킵)
  먼저 호출하도록 훅 추가.
- `skills/acpd/SKILL.md` — 위 훅 반영해 문서 갱신.
- `regression-tests/verify-issue-50.sh` — 신규. 9개 스크립트 × 4확장자
  존재 확인, SKILL.md의 `.sh` wrapper 호출 + 맨 `.py` 직접 호출 0건
  단언, **모델명 하드코딩 없음**(`log-cost-sonnet.sh` 같은 리터럴이
  SKILL.md 지시문에 없음) + **정확성 재사용 문구 존재** 단언(issue-50
  요구사항 0), 스크래치 픽스처로 실측(sonnet)/null(minimax)/dryrun
  동작·로컬 오프셋 타임스탬프 검증, `cost_summary` 합산 검증, 임시 git
  repo에서 `aacp.sh` 전체 흐름 시뮬레이션.
- `issues/issue-50.md` — 본 파일.

**스펙 이탈**: 없음. 단, 구현 중 issue-50 스코프 밖의 기존 버그를
하나 발견했다 — `aacp.sh`의 `TYPE_FILES` 배열 중 `__refix-plan.md`
엔트리는 glob 메타문자가 없는 리터럴 경로라 `nullglob`이 적용되지
않는다. 그 파일이 없으면(예: 순수 tdd2+acpd 플로우처럼 review 사이클을
거치지 않은 이슈) `git mv`가 그대로 실패한다. 이번 이슈 스코프가
아니므로 고치지 않았고, `verify-issue-50.sh`의 aacp 픽스처는 더미
`refix-plan.md`를 만들어 우회했다 — **별도 이슈로 보고 필요**.

**verify 결과**: `bash regression-tests/verify-issue-50.sh` 전체 PASS.
전체 회귀 스위트(`regression-tests/verify-issue-*.sh`) 중 11개
(21/22/24/26/33/34/38/39/41/47/48)가 실패하지만, 수정 전 베이스라인
(`git stash`로 이번 변경 제거 후 동일 스크립트 재실행)에서도 동일하게
실패함을 확인 — 이번 변경과 무관한 기존 실패. `python3 -m py_compile
tools/*.py` 전체 컴파일 클린. `pyproject.toml`이 저장소 루트에 없어
tdd2 규약에 따라 ruff/pyright 게이트는 자동 skip.
