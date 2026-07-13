# issue-47: agent-stats.json — review-stats.json + coding-stats.json 통합, started/archived/duration 도입
agent-tier: any

## 배경

grill 세션(2026-07-13) 합의. issue-41/44(리뷰어 축)와 issue-45/46(coder 축)이
각각 `issue-N__TYPE-review-stats.json`과 `issue-N__TYPE-coding-stats.json`을
서로 다른 두 시점(autotddreview Step 3 / tdd2 Step 5+11 + autotddreview
Step 3 병합)에 남기도록 설계했으나, 실제로 아직 한 번도 생성된 적이
없다(라이브·아카이브 어디에도 데이터 파일 0건 — 순수 스펙 상태).
데이터 마이그레이션 부담이 없는 지금이 스키마를 다시 잡을 적기라는 판단.

확정된 결정:

1. 두 파일을 **하나**로 합친다 — `issue-N__TYPE-agent-stats.json`.
2. 기존 최상위 단일 `date` 필드(review-stats.json, autotddreview Step 3가
   기록하던 시점 — 사실상 리뷰 판정 시점)를 **폐기**하고, 대신 이슈
   생명주기의 두 끝 — 시작/아카이브 — 을 각각 명시적으로 기록한다:
   `started`(ISO 8601 timestamp), `archived`(ISO 8601 timestamp),
   `duration`(ISO 8601 **duration**, 예: `PT26H15M`, `archived - started`).
3. `derived`(파생 이슈 파일명 목록) 필드를 `derived_by_reviewers`로 개명한다.

조사 중 드러난 기존 구멍(이 이슈에서 같이 메운다): `aacp.sh`/`.ps1`는
현재 `issue-N.md` 본 파일만 `git mv`로 아카이브하고, `__TYPE-*` 산출물
(code-review, refix-plan, review-stats.json/coding-stats.json)은 실제로
옮기는 로직이 없다 — autotddreview SKILL.md의 "aacp로 아카이브" 서술은
구현되지 않은 죽은 스펙이었다. `archived`/`duration`을 아카이브 스크립트가
직접 계산해 쓰려면, 그 스크립트가 TYPE 파일을 실제로 옮기는 지점이어야
한다. 이 김에 aacp.sh/.ps1가 `issue-N__TYPE-*`/`autofix-N__TYPE-*` 전체를
글롭으로 찾아 함께 아카이브하도록 만든다.

**선행**: issue-41(review-stats.json 스키마), issue-43(스코어보드 CLI),
issue-44(model 필드), issue-45/46(coding-stats.json 스키마). 이 이슈는
41/44/45/46이 정의한 스키마를 대체한다 — 실제 데이터가 없으므로 폐기가
아니라 재설계.

## 요구사항

### 1. `docs/spec/spec-issue-filenames.md` 갱신

- TYPE enum에서 `review-stats` / `coding-stats` 제거, `agent-stats` 추가.
- 예시 섹션의 두 예시 줄(`issue-21__TYPE-review-stats.json`,
  `issue-21__TYPE-coding-stats.json`)을
  `issue-21__TYPE-agent-stats.json` 한 줄로 교체.

### 2. `issue-N__TYPE-agent-stats.json` 스키마 확정

```json
{
  "issue": 47,
  "started": "2026-07-13T01:00:00Z",
  "archived": "2026-07-14T03:15:00Z",
  "duration": "PT26H15M",
  "reviewers": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "findings": 4,
      "must_fix": 0,
      "good_to_fix": 4,
      "gate_rejected": 0,
      "verify_rejected": 0
    }
  },
  "derived_by_reviewers": ["issue-48-fixing-47.md"],
  "coders": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "mvp": {
        "ts": "2026-07-13T01:30:50Z",
        "loc_added": 192,
        "static_analysis_failures": { "ruff": 0, "pyright": 0 }
      },
      "review_outcome": {
        "ts": "2026-07-13T21:40:00Z",
        "findings_received": 4,
        "must_fix_count": 0,
        "good_to_fix_count": 4,
        "refix_plans_written": 1
      }
    }
  }
}
```

- `reviewers`/`derived_by_reviewers` 서브트리는 issue-41/44가 정의한
  기존 review-stats.json 필드 의미를 그대로 유지(모델 필드, 전원 크레딧
  규칙 등 — issue-44 결정 불변), 필드명 `derived` → `derived_by_reviewers`만
  변경.
- `coders` 서브트리는 issue-46이 정의한 coding-stats.json 필드 의미를
  그대로 유지 — 변경 없음.
- `started`/`archived`/`duration`이 신규. `started`는 issue-레벨(단일
  값) — 여러 coder가 있어도 하나. `duration`은 `archived - started`를
  ISO 8601 duration으로 표현(초 단위 반올림 없이, 최소 단위는 초).
- 리뷰 사이클 없이(예: 셀프리뷰 없는 극단적 경우도 tdd2는 self-review
  서브에이전트를 반드시 거치므로 실무상 `reviewers`가 비는 경우는 없음
  — 있다면 빈 객체 `{}`로 기록, 침묵 금지).

### 3. `tdd2` SKILL.md 수정 (Step 5, Step 11)

파일: `.claude/skills/tdd2/SKILL.md`

- Step 5의 "coding-stats 계측" 문단을 다음으로 교체: `git rev-parse HEAD`를
  `<시작HEAD>`로 기록하는 바로 그 순간, ISO 8601 타임스탬프도 함께 얻어
  `issues/issue-<#N>__TYPE-agent-stats.json`을 **최초 생성**한다 —
  `{"issue": <N>, "started": "<타임스탬프>", "coders": {"<base명>": {"model": "<버전 포함 모델명>"}}}`.
  파일이 이미 존재하면(재실행 케이스) `started`/`issue`는 보존하고 덮어쓰지
  않는다. ruff/pyright 실패 카운팅 관행(세션 컨텍스트 내 카운터, 파일
  I/O 없음)은 그대로.
- Step 11의 "coding-stats.json 최초 생성" 문단을 "agent-stats.json의
  `coders.<base명>.mvp` 채움"으로 교체: 파일명을
  `issues/issue-<#N>__TYPE-agent-stats.json`으로, Step 5가 만들어 둔
  기존 `started`/`issue` 필드는 보존하며 `coders.<base명>.mvp`만
  덮어쓴다(`review_outcome`이 이미 있으면 보존 — 기존 규칙 유지).

### 4. `autotddreview` SKILL.md 수정 (Step 3, Step 4)

파일: `.claude/skills/autotddreview/SKILL.md`

- Step 3-7(review-stats JSON 기록)을 "agent-stats JSON 병합 기록"으로
  교체: 파일명을 `issue-N__TYPE-agent-stats.json`으로, Step 5/11이
  이미 만들어 둔 `issue`/`started`/`coders` 필드를 보존한 채
  `reviewers`와 `derived_by_reviewers`(구 `derived`) 필드를 병합 기록한다.
  `model`/전원 크레딧 등 기존 필드 규칙(issue-44) 문구는 그대로 옮긴다.
- Step 3-8(coding-stats JSON 병합 기록)을 "같은 파일의
  `coders.<base명>.review_outcome` 병합"으로 문구만 교체(파일이
  하나이므로 "병합 기록"이 사실상 Step 3-7과 한 파일에 대한 같은
  write 호출임을 명시).
- Step 4 "Done check"와 아카이브 목록에서 `review-stats.json`,
  `coding-stats.json` 두 언급을 `issue-N__TYPE-agent-stats.json`
  하나로 교체.
- Step 4의 "`aacp`를 사용해 아카이브"라는 서술을, 요구사항 5의 aacp.sh
  확장과 맞물리도록 단순화: "이 이슈의 `__TYPE-*` 산출물(code-review들,
  refix-plan, agent-stats.json)은 별도로 `git mv`하지 않는다 — 이 이슈에
  대해 `aacp`(`.claude/skills/acpd/aacp.sh`)를 호출하면 `issue-N.md`와
  함께 자동으로 아카이브된다."로 교체(요구사항 5 참조).

### 5. `aacp.sh`/`.ps1` 확장 — TYPE 파일 일괄 아카이브 + agent-stats.json 특별 처리

파일: `.claude/skills/acpd/aacp.sh`, `.claude/skills/acpd/aacp.ps1`
(`.bat`는 `.ps1` 디스패처이므로 로직 변경 없음)

- 기존 "2. Archive" 스텝(현재 `issue-N.md`만 `git mv`) 바로 다음에 추가:
  `issues/${STREAM}-${N}__TYPE-*` 패턴에 매칭하는 **살아있는**(이미
  archive/ 하위가 아닌) 파일을 전부 찾는다.
  - 파일명이 `__TYPE-agent-stats.json`으로 끝나면: `git mv`하기 **전에**
    `uv run tools/agent-stats-archive.py "$REPO_ROOT" "${STREAM}-${N}"`를
    호출해 `archived`/`duration`을 채운 뒤(요구사항 6), 그 다음에 같은
    `ARCHIVE_DIR`로 `git mv`.
  - 그 외 `__TYPE-*` 파일(code-review, refix-plan 등)은 그대로
    `ARCHIVE_DIR`로 `git mv`(파일명 불변).
  - 매칭되는 `__TYPE-*` 파일이 하나도 없어도(review 사이클 없이 순수
    /tdd2 + /acpd만 거친 경우) 에러 아님 — 조용히 건너뜀.
- `.ps1` 포트는 `.sh`와 동일 로직(글롭, agent-stats.json 특별 처리,
  나머지 파일 일괄 이동).

### 6. 신규 헬퍼: `tools/agent-stats-archive.py`

- `tools/reviewer-scoreboard.py`와 동일 관례: PEP 723 인라인 메타데이터
  (`# /// script` / `requires-python` / `dependencies = []`), 표준
  라이브러리만 사용.
- 사용법: `agent-stats-archive.py <repo-path> <issue-N|autofix-N>`.
- 동작: `issues/${STREAM}-${N}__TYPE-agent-stats.json`을 읽어
  (없으면 에러 종료, 침묵 금지) `archived`에 현재 UTC ISO 8601
  타임스탬프를, `duration`에 `archived - started`를 ISO 8601 duration
  문자열(예: `PT26H15M`, 날짜 경계를 넘으면 `P1DT2H3M`)로 계산해 채운
  뒤 같은 경로에 덮어쓴다. `started` 필드가 없으면 에러 종료(구조적
  전제 위반).
- 종료 코드로 성공/실패 신호(호출자 aacp.sh가 `set -euo pipefail`이므로
  실패 시 아카이브 전체가 중단되어야 함).

### 7. `tools/reviewer-scoreboard.py` 갱신

- `collect()`의 글롭을 `*__TYPE-review-stats.json`에서
  `*__TYPE-agent-stats.json`으로, `collect_coders()`의 글롭을
  `*__TYPE-coding-stats.json`에서 동일하게 `*__TYPE-agent-stats.json`으로
  교체 — **한 파일을 두 함수가 각자 필요한 서브트리(`reviewers`/`coders`)만
  읽는 방식**으로 통합(파일을 두 번 읽어도 무방 — 손상 파일 처리 로직이
  함수별로 이미 분리돼 있으므로 재사용 최소 변경).
- `--since` 필터 기준 필드를 `date`에서 `started`로 변경(`collect()`와
  `collect_coders()` 양쪽 다 동일 필드 사용하도록 통일 — 현재
  `collect_coders()`는 `mvp.ts`/`review_outcome.ts` 중 최댓값을 쓰고
  있었는데, 이제 이슈 레벨 `started`로 일원화해 두 함수가 같은 파일의
  같은 필드를 기준으로 필터링하게 만든다).
- `data.get("derived")` 등 옛 필드명을 직접 참조하는 코드는 없음(현재
  `collect()`는 `derived`를 읽지 않음 — 확인됨). 스코어보드 출력에
  `derived_by_reviewers` 개수 등을 새로 추가할 필요는 없음(요구사항
  범위 밖).

### 8. 하지 말 것

- review-stats.json/coding-stats.json 하위 호환 코드(구 파일명 glob도
  같이 지원 등)를 만들지 않는다 — 실제 생성된 데이터가 전무하므로
  마이그레이션 대상이 없다.
- `reviewers`/`coders` 서브트리 내부의 기존 필드 의미(issue-41/44/45/46
  결정)는 건드리지 않는다 — 필드명 변경은 `derived`→`derived_by_reviewers`
  단 하나.
- `duration`을 `reviewer-scoreboard.py`가 매번 재계산하는 파생값으로
  만들지 않는다 — 원본 파일에 영구 저장(요구사항 6이 유일한 계산 지점).

## 승인 기준

- [ ] `spec-issue-filenames.md`: TYPE enum에 `agent-stats`, `review-stats`/
      `coding-stats` 완전 제거, 예시 줄 교체
- [ ] `tdd2` SKILL.md Step 5: `started` 타임스탬프 기록 + agent-stats.json
      최초 생성 서술, Step 11: `coders.*.mvp` 채움으로 파일명·문구 갱신
- [ ] `autotddreview` SKILL.md Step 3: `reviewers`+`derived_by_reviewers`
      병합 기록 서술(파일명 agent-stats.json), Step 4: done-check·아카이브
      목록에서 옛 파일명 완전 제거 + aacp 위임 문구로 교체
- [ ] `aacp.sh`/`.ps1`: `__TYPE-*` 글롭 아카이브 로직 추가,
      `agent-stats.json`은 `tools/agent-stats-archive.py` 호출 후 이동
- [ ] `tools/agent-stats-archive.py` 신규 — PEP723, stdlib만,
      archived/duration 계산·덮어쓰기, `started` 없으면 에러 종료
- [ ] `tools/reviewer-scoreboard.py`: 글롭 통합, `--since` 기준 `started`로
      통일, 기존 집계 결과(픽스처 기준) 불변
- [ ] `tests/test_reviewer_scoreboard.py`,
      `tests/test_reviewer_scoreboard_coder.py`: 새 스키마·파일명 픽스처로
      갱신
- [ ] `regression-tests/verify-issue-39/41/43/44/45/46.sh` 중 옛 파일명·
      필드를 직접 assert하는 부분 갱신 또는 폐기+conflict 문서화
      (issue-46이 verify-issue-45.sh에 한 방식 참고)
- [ ] 전체 회귀 PASS, `uv run --with pytest pytest tests/` PASS,
      ruff+pyright 클린

## 검증

`regression-tests/verify-issue-47.sh`:
- `spec-issue-filenames.md`에 `agent-stats` 존재, `review-stats`/
  `coding-stats` 문자열 0건 단언.
- `tdd2`/`autotddreview` SKILL.md에 `agent-stats.json`, `started`,
  `derived_by_reviewers` 문구 존재, 옛 파일명 언급 0건 단언.
- 픽스처 `issue-N__TYPE-agent-stats.json`(started만 있는 것 / started+
  archived+duration 다 있는 것 / reviewers+coders 둘 다 있는 것)으로
  `tools/agent-stats-archive.py`를 실행 — `archived`/`duration`이
  올바르게 채워지는지, `started` 없는 픽스처는 에러 종료하는지 단언.
- 같은 픽스처들로 `tools/reviewer-scoreboard.py --json` 실행 — reviewers/
  coders 양쪽 집계가 기존 결과와 동일한 수치인지, `--since`가 `started`
  기준으로 정확히 필터링하는지 단언.
- `aacp.sh`(임시 git repo에서)로 가짜 issue-N.md + agent-stats.json +
  code-review 픽스처를 아카이브 — 셋 다 archive/ 아래로 이동했는지,
  agent-stats.json의 `archived`/`duration`이 채워졌는지 단언.
- pytest 게이트 통과.

## 구현 결과

**구현 완료 일시**: 2026-07-13T04:45:00Z
**변경 파일**:
- `docs/spec/spec-issue-filenames.md` — TYPE enum에 `agent-stats` 추가, `review-stats`/`coding-stats` 완전 제거, 예시 줄 통합
- `.claude/skills/tdd2/SKILL.md` — Step 5: `started` 타임스탬프 기록 + agent-stats.json 최초 생성(issue/started/coders 골격), Step 11: `coders.*.mvp` 채움으로 문구·파일명 갱신
- `/home/user1/.claude/skills/tdd2/SKILL.md` — 전역 스킬 동기화
- `.claude/skills/autotddreview/SKILL.md` — Step 3-7/3-8: agent-stats.json 병합 기록(`reviewers`+`derived_by_reviewers`+`coders.*.review_outcome`, 같은 파일에 대한 한 번의 write), Step 4: done-check·아카이브 목록을 agent-stats.json 하나로, "aacp 호출로 TYPE 파일 일괄 아카이브" 문구로 교체
- `/home/user1/.claude/skills/autotddreview/SKILL.md` — 전역 스킬 동기화
- `.claude/skills/acpd/SKILL.md` — `__TYPE-*` 산출물 동반 아카이브 문구 추가
- `/home/user1/.claude/skills/acpd/SKILL.md` — 전역 스킬 동기화
- `.claude/skills/acpd/aacp.sh` — 2.5단계 신설: 이슈의 살아있는 `__TYPE-*` 파일을 전부 글롭으로 찾아 `git mv`; `agent-stats.json`은 이동 직전 헬퍼 호출로 `archived`/`duration` 스탬프
- `.claude/skills/acpd/aacp.ps1` — 동일 로직 PowerShell 포트
- `/home/user1/.claude/skills/acpd/aacp.sh`, `/home/user1/.claude/skills/acpd/aacp.ps1` — 전역 스킬 동기화
- `.claude/skills/acpd/defaults/agent-stats-archive.py` — 신규. PEP723 인라인 메타데이터, stdlib만. `started` 기준으로 `archived`(UTC ISO8601)·`duration`(ISO8601 duration) 계산해 같은 파일에 덮어씀. `started` 없으면 에러 종료
- `/home/user1/.claude/skills/acpd/defaults/agent-stats-archive.py` — 전역 스킬 동기화
- `tools/reviewer-scoreboard.py` — `collect()`/`collect_coders()` 글롭을 `*__TYPE-agent-stats.json` 하나로 통합, `--since` 필터 기준을 양쪽 다 `started`로 통일, `reviewers` 키 부재(코더 전용 이슈)를 손상 아닌 정상으로 처리하도록 수정, 미사용 `_EMPTY_CODER` 죽은 코드 제거
- `tests/test_agent_stats_archive.py` — 신규 7건(정상 계산, 하루 경계 duration, 짧은 duration, 기존 필드 보존, started 누락 에러, 파일 없음 에러, 잘못된 스트림 ID, autofix 스트림)
- `tests/test_reviewer_scoreboard.py` — 픽스처를 agent-stats.json/`started`/`derived_by_reviewers`로 갱신, "리뷰 없는 정상 파일은 경고 없음" 테스트 1건 추가
- `tests/test_reviewer_scoreboard_coder.py` — 픽스처를 agent-stats.json으로 갱신, `--since` 테스트를 top-level `started` 기준으로 재작성, "`coders` 필드 자체가 없으면 경고" 테스트 1건 추가
- `regression-tests/verify-issue-39/41/43/44/46.sh` — 옛 파일명·필드(`review-stats.json`/`coding-stats.json`/`date`/`derived`) 참조를 새 스키마로 갱신(스크립트 자체의 검증 의도는 보존, 폐기 아님)
- `regression-tests/verify-issue-{39,41,43,44,46}.conflict-with-47.md` — 각 스크립트 갱신 사유 문서화
- `regression-tests/verify-issue-47.sh` — 신규 31개 단언(spec, SKILL.md 로컬+전역, 헬퍼 stdlib-only·정상/에러 케이스, 스코어보드 통합 집계·경고 억제·--since, aacp 실제 실행 스모크 테스트, pytest 게이트)
- `issues/issue-47.md` — 본 파일, 구현 결과 갱신

**스펙 이탈**:
1. `tools/agent-stats-archive.py`로 계획했던 헬퍼 위치를
   `.claude/skills/acpd/defaults/agent-stats-archive.py`로 변경. 이유:
   `aacp.sh`는 acpd 스킬과 함께 다른 target repo에도 배포되는 스크립트인데,
   `tools/`는 이 autotdd 리포 자신의 최상위 디렉터리라 다른 리포에는
   따라가지 않는다 — `tools/`에 두면 다른 프로젝트에서 `/acpd`를 쓸 때
   헬퍼가 없어 아카이브 단계가 깨진다. `run-ruff.sh` 등 기존
   `defaults/*` 관례와 동일하게 스킬 패키지 안으로 옮겼다.
2. `duration` 포맷 예시가 이슈 본문에서 자기모순이었다(`PT26H15M`는
   비정규화, "날짜 경계 시 P1DT2H3M"는 정규화 — 둘 다 26시간대 예로
   등장). 정규화(날짜 경계를 넘으면 항상 `P<n>D` 성분을 쓰고 시간은
   0~23 범위)로 통일해 구현했다.
3. `reviewer-scoreboard.py`의 `collect()`가 `reviewers` 키 자체가 없는
   파일(순수 `/tdd2`+`/acpd`만 거쳐 리뷰 사이클이 없었던 이슈)을 조용히
   건너뛰도록(경고 없이) 구현했다. 이슈 본문의 "실무상 reviewers가 비는
   경우는 없음" 서술은 부정확했다 — 아카이브를 조사해 보니 issue-16/20/21
   등 일부만 리뷰 사이클(autotddreview)을 거쳤고, 대다수 과거 이슈는
   순수 tdd2+acpd만 거쳐 영구적으로 `reviewers`가 없다. 이를 매번
   "손상 파일" 경고로 잘못 보고하지 않도록 정정했다.

**verify 결과**: `bash regression-tests/verify-issue-47.sh` 31/31 PASS.
전체 회귀 `regression-tests/verify-issue-*.sh` 43개 전부 PASS(신규 5개
conflict 문서 포함). `uv run --with pytest pytest -q tests/` 21/21 PASS.
`uv run --with ruff ruff check .` — 이번 변경 파일 전부 클린(기존
`autoqafix` 쪽 무관 파일 4건은 이 이슈 이전부터 있던 잔여 lint 부채,
손대지 않음). `uv run --with pyright pyright tools/reviewer-scoreboard.py
.claude/skills/acpd/defaults/agent-stats-archive.py` 0 errors.
`uv run python -m compileall` 클린. `aacp.sh`는 스크래치 git repo에서
실제 실행해 `__TYPE-*` 아카이브 및 `archived`/`duration` 스탬프 동작을
직접 확인.
