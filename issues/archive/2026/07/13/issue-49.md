# issue-49: agent-stats.json에 cost_details/cost_summary 추가 — 단계별 5h/7d 쿼터 계측
agent-tier: any

## 배경

grill 세션(2026-07-13) 합의. `/autotdd`만 반복 실행한 뒤 나중에 한 번
review/fix를 돌리는 방식과, `/autotddreviewfix`(구현→리뷰→플랜→refix 4단계
루프)를 매 이슈마다 도는 방식 중 어느 쪽이 나은지 판단하려면 review/fix
루프 자체의 오버헤드(쿼터 소모량)를 실측해야 한다. 지금까지
`agent-stats.json`(issue-47)은 `coders`/`reviewers` 축의 산출물 품질(LOC,
정적분석 실패, finding 수 등)만 기록했고, **각 단계를 실행한 모델이 그
시점에 5시간/7일 쿼터를 얼마나 쓰고 있었는지**는 기록하지 않았다.

**grill 합의 결정 요약**:
- `cost_details`는 `mvp`/`review`/`refix-plan`/`refix` 4단계 각각의
  전/후 시점에 이벤트를 append하는 **감사 로그**다 — 사용량을 조회할
  수단이 없는 모델(minimax/qwen/deepseek)이어도 항목 자체는 반드시
  남기고 pct만 `null`로 채운다(침묵 금지).
- "모델"은 **그 단계를 실제로 수행한 모델**(coder/reviewer 각각) —
  오케스트레이팅 세션 자신이 아니다. review(Step2)는 리뷰어별로 개별
  before/after 쌍(N명이면 2N항목), refix(Step4)는 파생 이슈 개수와
  무관하게 원본 이슈에 **한 쌍만**(각 파생 이슈 자신의 mvp 비용은 그
  이슈 자신의 `agent-stats.json`에 이미 기록되므로 중복 계측 방지).
- 필드명은 실제 쿼터 창 길이를 반영: `five_hour_used_pct`(5시간 창),
  `seven_day_used_pct`(7일 창 — "weekly"·"hourly" 대신 정확한 창 이름).
- 조회 소스는 `claude-dashboard` 플러그인의 `check-usage --json`
  (`claude`/`gemini` provider만 실측 가능; minimax/qwen/deepseek는
  조회 수단 자체가 없음).
- 스크립트는 base명(`sonnet`/`opus`/`haiku`/`fable`/`gemini`/`minimax`/
  `qwen`/`deepseek`) **각각 하나씩** 자기완결적으로 만들고, 공통 Pydantic
  모델로 출력 스키마를 통일한다. `--dryrun` 옵션으로 실제 기록 없이
  계산만 확인할 수 있어야 한다.
- `cost_summary`는 별도 스크립트(`log-cost-summary.py`)가 이슈의 모든
  LLM 작업이 끝난 aacpd 아카이브 시점에 `cost_details`를 스캔해 계산한다
  (기존 `agent-stats-archive.py`가 `archived`/`duration`을 채우는 것과
  같은 훅, 그 직전).

## 요구사항

### 1. 공통 라이브러리 `tools/cost_entry.py`

- Pydantic 모델 `CostDetailEntry`: `ts`(ISO8601) / `model`(base명) /
  `five_hour_used_pct`(float|None) / `seven_day_used_pct`(float|None) /
  `description`(str).
- `find_stats_file(repo, target)` — `issues/<stream>-<N>__TYPE-agent-stats.json`
  경로 결정(agent-stats-archive.py와 동일한 `issue|autofix` 정규식).
- `append_cost_detail(...)` — 대상 파일을 읽어 `cost_details` 배열에
  entry를 append하고 다시 쓴다. `dryrun=True`면 entry는 구성하되 파일은
  쓰지 않고 (경로, entry)만 반환.
- `query_check_usage_pct(provider_key)` — `~/.claude/plugins/cache/claude-dashboard/claude-dashboard/*/dist/check-usage.js --json`을
  호출해 `provider_key`(`claude`/`gemini`)의 `fiveHourPercent`/
  `sevenDayPercent`를 얻는다. 조회 실패(플러그인 없음/node 실패/provider
  미설치)는 모두 `(None, None)` + stderr 경고(침묵 금지).

### 2. base명별 스크립트 8개 — `tools/log-cost-<base>.py`

`sonnet`/`opus`/`haiku`/`fable`/`gemini`/`minimax`/`qwen`/`deepseek`.

- CLI: `log-cost-<base>.py [--dryrun] <repo-path> <issue-N|autofix-N> "<description>"`.
- `sonnet`/`opus`/`haiku`/`fable` — `query_check_usage_pct("claude")` 호출.
- `gemini` — `query_check_usage_pct("gemini")` 호출.
- `minimax`/`qwen`/`deepseek` — 조회 시도 없이 `five_hour_used_pct`/
  `seven_day_used_pct`를 하드코딩 `None`으로 기록(미지원 provider임을
  출력 메시지에 명시).
- 모두 PEP723 인라인 메타데이터(`dependencies = ["pydantic"]`), 실패해도
  exit code로 명확히 신호(파일 없음/파싱 불가 등은 exit 1 + stderr).

### 3. `tools/log-cost-summary.py`

- CLI: `log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>`.
- `cost_details`를 모델별로 그룹화해 `five_hour_sum`/`seven_day_sum`을
  계산(`null` 값은 합산에서 제외, 전부 `null`이면 합산 결과도 `null`).
- 결과를 `cost_summary` 필드에 써서 저장(`--dryrun`이면 계산만 출력).

### 4. `tdd2/SKILL.md` — mvp 전후 계측

- Step 5(agent-stats.json 최초 생성 직후): "before mvp" 이벤트 기록
  지시 추가.
- Step 11(`coders.<base명>.mvp` 채움 직후): "after mvp" 이벤트 기록
  지시 추가.

### 5. `autotddreviewfix/SKILL.md` — review/refix-plan/refix 전후 계측

- Step 2(Reviewers): 리뷰어별 개별 before/after 쌍(외부 리뷰어는
  `<X>-cli.sh` 호출 전후, self-review는 서브에이전트 launch 전후 —
  오케스트레이터 자신의 base명 사용).
- Step 3(Planner): 시작 직후 "before refix-plan", `review_outcome` 병합
  직후 "after refix-plan"(오케스트레이터 자신의 base명).
- Step 4(Coder re-fix): 파생 이슈 처리 시작 전 "before refix", 전부
  끝난 직후 "after refix" — 파생 이슈 개수와 무관하게 **한 쌍만**.

### 6. `aacpd/aacp.sh` — cost_summary 계산 훅

- `issue-N__TYPE-agent-stats.json`을 archive 디렉터리로 `git mv`하기
  직전, 기존 `agent-stats-archive.py` 호출 **바로 앞**에
  `uv run tools/log-cost-summary.py "$REPO_ROOT" "${STREAM}-${N}"`를
  추가한다.
- `aacpd/SKILL.md` 문서도 이 새 훅을 반영해 갱신한다.

### 7. 하지 말 것

- `coders`/`reviewers`/`derived_by_reviewers` 등 기존 agent-stats.json
  필드의 의미·형식 변경(issue-43~47이 이미 확정한 스키마는 그대로).
- minimax/qwen/deepseek를 위한 대체 사용량 조회 수단을 이번에 새로
  만들기(harness-project 쪽 조사는 범위 밖 — null 기록으로 충분).
- reviewer-scoreboard.py 등 다른 도구의 집계 로직 변경.

## 승인 기준

- [ ] `tools/cost_entry.py` 신규: `CostDetailEntry`(Pydantic) +
      `append_cost_detail`(dryrun 지원) + `query_check_usage_pct`.
- [ ] `tools/log-cost-{sonnet,opus,haiku,fable,gemini,minimax,qwen,deepseek}.py`
      8개 신규, 각각 `--dryrun` 지원, 대상 이슈의 `cost_details`에
      append.
- [ ] `tools/log-cost-summary.py` 신규: 모델별 `five_hour_sum`/
      `seven_day_sum` 계산해 `cost_summary`에 기록, `--dryrun` 지원.
- [ ] `tdd2/SKILL.md`: Step 5/11에 before/after mvp 계측 지시 존재.
- [ ] `autotddreviewfix/SKILL.md`: Step 2(리뷰어별)/Step 3/Step 4에
      before/after 계측 지시 존재, Step 4는 파생 이슈 전체를 감싸는
      한 쌍만.
- [ ] `aacpd/aacp.sh`: `agent-stats-archive.py` 호출 직전
      `log-cost-summary.py` 호출 존재. `aacpd/SKILL.md` 동기화.
- [ ] `regression-tests/verify-issue-49.sh`: 8개 스크립트 + summary
      스크립트 실제 호출(스크래치 픽스처) + aacp.sh 전체 훅 흐름 시뮬레이션
      + SKILL.md grep 단언.

## 검증

`bash regression-tests/verify-issue-49.sh`:
- 스크래치 `issues/issue-<N>__TYPE-agent-stats.json` 픽스처에
  `log-cost-sonnet.py`(실측) + `log-cost-minimax.py`(null) 호출 →
  `cost_details`에 정확한 항목 append 확인.
- `--dryrun` 호출은 파일을 변경하지 않음을 확인.
- `log-cost-summary.py` 호출 후 `cost_summary`가 모델별로 정확히
  합산됨을 확인(null 제외, 전부 null이면 결과도 null).
- 임시 git repo에서 `aacp.sh`를 끝까지 실행해 `cost_summary`가
  `archived`/`duration`과 함께 최종 아카이브 파일에 존재함을 확인.
- `tdd2`/`autotddreviewfix`/`aacpd` SKILL.md에 관련 지시 문구 존재.

## 구현 결과

**구현 완료 일시**: 2026-07-13T20:30:38Z
**변경 파일**:
- `tools/cost_entry.py` — 신규. `CostDetailEntry`(Pydantic) 모델,
  `append_cost_detail`(dryrun 지원 — dryrun이면 대상 파일 존재 여부와
  무관하게 entry만 계산해 반환), `query_check_usage_pct`(claude-dashboard
  check-usage.js 호출 헬퍼).
- `tools/log-cost-sonnet.py` / `log-cost-opus.py` / `log-cost-haiku.py` /
  `log-cost-fable.py` — 신규. `claude` provider 실측.
- `tools/log-cost-gemini.py` — 신규. `gemini` provider 실측.
- `tools/log-cost-minimax.py` / `log-cost-qwen.py` / `log-cost-deepseek.py` —
  신규. 조회 수단 없음 — `null` 하드코딩 기록.
- `tools/log-cost-summary.py` — 신규. `cost_details` → 모델별
  `five_hour_sum`/`seven_day_sum` 계산, `cost_summary`에 기록.
- `tools/log-cost-{sonnet,opus,haiku,fable,gemini,minimax,qwen,deepseek,summary}.{sh,bat,ps1}` —
  신규 27개. 각 `.py`가 PEP723 인라인 의존성(`pydantic`)을 선언하므로
  반드시 `uv run`을 거쳐야 하는데, SKILL.md 프로즈만으로는 이 사실이
  드러나지 않아 맨 `python3 tools/log-cost-*.py` 직접 호출 시
  `ModuleNotFoundError`가 날 수 있었다 — 셋 다 `uv run <같은 .py>
  "$@"`로 감싸는 얇은 wrapper(호출부 CWD와 무관하게 자기 디렉터리를
  resolve).
- `.claude/skills/tdd2/SKILL.md` — Step 5/11에 "before mvp"/"after mvp"
  계측 지시 추가(`.sh` wrapper 호출, Windows `.bat`/`.ps1` 안내).
- `.claude/skills/autotddreviewfix/SKILL.md` — Step 2(리뷰어별 개별
  before/after review), Step 3(before/after refix-plan), Step 4(파생
  이슈 전체를 감싸는 한 쌍의 before/after refix) 계측 지시 추가(`.sh`
  wrapper 호출).
- `.claude/skills/aacpd/aacp.sh` — `agent-stats-archive.py` 호출 직전
  `tools/log-cost-summary.py` 호출 추가. `tools/log-cost-summary.py`가
  없는 대상 repo(예: 샌드박스 테스트)에서도 깨지지 않도록 `deploy.sh`와
  같은 "있으면 실행, 없으면 스킵" 방식으로 존재 여부를 먼저 확인한다.
- `.claude/skills/aacpd/aacp.ps1` — 동일 훅을 PowerShell 쪽에도 추가
  (`Test-Path`로 존재 확인 후 `uv run`).
- `.claude/skills/aacpd/SKILL.md` — 위 훅 반영해 문서 갱신.
- `regression-tests/verify-issue-49.sh` — 신규 회귀 스크립트(9개 스크립트
  × 4확장자 존재 확인, SKILL.md의 `.sh` wrapper 호출 단언 + 맨 `.py`
  직접 호출 0건 단언, 스크래치 픽스처로 wrapper 실동작 검증, aacp.sh
  전체 흐름 시뮬레이션 포함).
- `issues/issue-49.md` — 본 파일.

**스펙 이탈**: 사용자가 구현 도중 두 가지를 추가 요청해 반영했다(원
요구사항 대비 확장이지 이탈 아님):
1. **uv run wrapper 27개 추가**: 원 계획은 `tools/log-cost-*.py`를 직접
   호출하는 것이었으나, pydantic 의존성 때문에 맨 `python3` 호출이
   실패할 수 있음을 지적받아 `.sh`/`.bat`/`.ps1` wrapper를 전부 추가하고
   SKILL.md 호출부를 `.sh`로 교체했다.
2. **`--dryrun`이 대상 파일 부재를 에러로 처리하던 버그 수정**: 사용자가
   `tools/log-cost-haiku.sh --dryrun . issue-49 "test"` 실행 시
   "파일 없음" 에러를 직접 재현해 보고했다. `--dryrun`은 애초에 기록을
   하지 않으므로 대상 파일 존재가 불필요한데 `append_cost_detail`이
   무조건 파일을 먼저 찾고 있었다 — dryrun 분기를 파일 조회보다 앞으로
   옮기고, 출력도 Python dict repr 대신 `model_dump_json`/`json.dumps`로
   실제 JSON을 콘솔에 표시하도록 고쳤다(9개 스크립트 전부 동일 적용).

**verify 결과**: `bash regression-tests/verify-issue-49.sh` 전체 PASS,
전체 회귀 스위트(`regression-tests/verify-issue-*.sh` 전부) PASS —
9개 스크립트 × wrapper 4종(.py/.sh/.bat/.ps1) 존재 확인, SKILL.md가
`.sh` wrapper를 호출하고 맨 `.py` 직접 호출이 0건임을 단언, `.sh`
wrapper를 스크래치 픽스처에 직접 호출해 실측(sonnet)·null(minimax)·
`--dryrun`(파일 불변, 파일 부재에도 에러 없이 JSON 출력)·`cost_summary`
합산(null 제외)을 모두 확인했고, 임시 git repo에서 `aacp.sh`를 끝까지
실행해 `cost_summary`가 `archived`/`duration`과 함께 최종 아카이브
파일에 존재함을 확인했다. 사용자가 보고한 재현 명령
(`tools/log-cost-haiku.sh --dryrun . issue-49 "test"`)도 직접 재실행해
에러 없이 JSON을 출력하고 파일을 건드리지 않음을 확인했다.
`pyproject.toml`이 저장소 루트에 없어 aacpd의 ruff/pyright/pytest
게이트는 tdd2/aacpd 규약에 따라 자동 skip(본 회귀 스크립트 자체가
독립적으로 검증 수행; `python3 -m py_compile tools/*.py`로 전체 컴파일
클린 확인).
