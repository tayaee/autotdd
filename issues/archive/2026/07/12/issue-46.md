# issue-46: coding-stats.json — coder 2회 평가(정적분석+리뷰 결함) 단일 파일 통합, coder-stats.jsonl 대체
agent-tier: any

## 배경

grill 세션(2026-07-12, ai-md 리포에서 autotddreview 실행 중 파생) 합의.
issue-45가 coder 축 정량화(log-run.sh + `issue-N__TYPE-coder-stats.jsonl`
append-only 로그 + 스코어보드 coder 섹션)를 이미 구현했으나, 다음 두
문제가 드러났다:

1. **배포 구멍**: issue-45의 tdd2 SKILL.md 텍스트 변경(Step 5/11의
   coder-stats 계측 서술)은 전역 스킬(`~/.agents/skills`)에 반영됐지만,
   그 서술이 참조하는 `log-run.sh` 스크립트 자체와 autotddreview의
   아카이브 목록 갱신은 전역에 배포되지 않았다. 즉 이 리포 밖(예: ai-md)
   에서 `/tdd2`가 Python 프로젝트를 다루면 존재하지 않는 `log-run.sh`를
   참조하는 죽은 스펙이 된다.
2. **설계 공백**: issue-45의 defect 밀도는 정적분석(ruff/pyright) 실패만
   센다. 리뷰에서 지적받아 "방어(재검증) 후 남은" must-fix 건수 —
   coder의 실제 결함으로 인정된 것 — 는 review-stats.json에만 있고
   coder-stats.jsonl과 연결되지 않는다. coder는 실제로 **두 번** 평가를
   받는다: ① MVP 구현 도중 정적분석 도구에 걸린 것, ② 리뷰에서 지적받아
   재검증까지 통과한(=accepted) 것. 이 둘을 한 coder 식별자 아래 모아야
   "이 모델이 기초 코딩 실력이 부족한지"를 온전히 판단할 수 있다.

append-only JSONL(issue-45)은 "이벤트 로그"에 적합한 형태이지 "한 이슈의
coder 성적표"를 담기엔 맞지 않는다. 대신 **이슈 1건당 1개의 단일 JSON
레코드**를 파이프라인의 두 시점에서 순서대로 갱신(read-modify-write)하는
편이 review-stats.json과 대칭적이고 소비(스코어보드)도 단순해진다.

**선행**: issue-41 (review-stats.json 스키마 — 이 이슈가 그대로 참고하는
자매 설계), issue-43 (스코어보드 CLI — coder 섹션 갱신 대상),
issue-45 (대체 대상 — log-run.sh/coder-stats.jsonl 폐기).

## 요구사항

### 1. 새 산출물 정의: `issue-N__TYPE-coding-stats.json`

`docs/spec/spec-issue-filenames.md`의 TYPE enum에 `coding-stats` 추가
(`coder-stats`는 제거하고 대체 — 예시 줄도 교체).

스키마 (이슈 1건당 1파일, `coders` 아래 coder base명별 서브트리):

```json
{
  "issue": 46,
  "coders": {
    "sonnet5": {
      "model": "Claude Sonnet 5",
      "mvp": {
        "ts": "2026-07-13T01:30:50Z",
        "loc_added": 192,
        "static_analysis_failures": { "ruff": 0, "pyright": 0 }
      },
      "review_outcome": {
        "ts": "2026-07-12T21:40:00Z",
        "findings_received": 4,
        "must_fix_count": 0,
        "good_to_fix_count": 4,
        "refix_plans_written": 1
      }
    }
  }
}
```

- `mvp.static_analysis_failures.<tool>`은 해당 프로젝트에 `pyproject.toml`
  이 없어 해당 도구가 아예 실행되지 않은 경우 `null`로 기록한다(0과
  구분 — "실행해서 0건"과 "실행 안 함"은 다른 신호).
- `review_outcome.must_fix_count`는 Step 3의 **실질 재검증까지 통과한**
  건수(= 파생 이슈로 물화된 must-fix 수)만 센다. 게이트·재검증에서
  reject된 것은 포함하지 않는다.
- `refix_plans_written`은 이 이슈 사이클에서 플래너가 refix-plan을 썼으면
  1, 리뷰 파일이 하나도 없어 플랜 자체를 못 썼으면 0.

### 2. `tdd2` SKILL.md 수정 (1차 기록 지점)

- Step 5의 `log-run.sh` 경유 지시를 제거한다. 대신: ruff/pyright 각각
  실패해 "restart from 5"할 때마다 **실행 세션이 자기 작업 컨텍스트
  안에서** 카운터를 증가시킨다(파일 I/O 없음 — 토큰 비용 최소화가
  목적). `pytest`/회귀 스크립트는 여전히 계측 대상이 아니다(issue-45
  결정 유지: TDD red는 의도된 실패).
- 시작 시 `git rev-parse HEAD`를 `<시작HEAD>`로 기록하는 관행(issue-45)
  은 유지 — `loc_added` 산출에 계속 필요.
- Step 11(구현 결과 갱신 직전)에서 `issues/issue-<#N>__TYPE-coding-stats.json`
  을 **새로 생성**한다: `coders.<base명>.model` + `coders.<base명>.mvp.*`
  (위 스키마). 파일이 이미 존재하면(드문 재실행 케이스) `mvp` 섹션만
  덮어쓰고 `review_outcome`이 있으면 보존한다.

### 3. `autotddreview` SKILL.md 수정 (2차 기록 지점)

- Step 3(플래너)이 must-fix/good-to-fix 분류를 마친 직후 — 즉
  `review-stats.json`을 쓰는 바로 그 시점에, 이미 계산된 값(추가 리뷰
  파일 재파싱 없음)으로 기존 `issues/issue-<N>__TYPE-coding-stats.json`
  을 읽어 `coders.<base명>.review_outcome`을 병합해 다시 쓴다. `<base명>`
  은 그 파일의 기존 `coders` 키(Step 1의 tdd2가 이미 써둔 것)를 그대로
  쓴다 — 새 coder를 추가하지 않는다.
- 리뷰 파일이 하나도 없어 애초에 refix-plan을 못 쓰는 예외 상황이면
  `review_outcome.refix_plans_written = 0`과 함께 나머지 필드를 0으로
  채워 기록한다(침묵 금지).
- Step 4의 done-check·아카이브 목록에 `issue-N__TYPE-coding-stats.json`
  추가 (기존 `review-stats.json`과 동일한 취급 — `git mv`로 파일명 그대로
  아카이브).

### 4. issue-45 잔재 제거

- `.claude/skills/acpd/defaults/log-run.sh`(+`.bat`/`.ps1`) 삭제 — 더 이상
  아무 스텝도 호출하지 않는 죽은 스크립트가 되므로.
- `tdd2`/`autotddreview` SKILL.md에서 `log-run.sh`/`coder-stats.jsonl`
  언급을 전부 제거(치환이 아니라 삭제 — 위 1~3항이 그 자리를 대신함).

### 5. `tools/reviewer-scoreboard.py` (issue-43/45) coder 섹션 갱신

- `*__TYPE-coder-stats.jsonl` 수집 로직을 `*__TYPE-coding-stats.json`
  수집으로 교체 (라이브+아카이브 재귀, 손상 파일은 경고 후 계속 —
  기존 review-stats 수집과 동일한 관용 정책).
- coder(model)별 집계: 이슈 수, `loc_added` 합, `static_analysis_failures`
  합(ruff/pyright 분리 유지), `must_fix_count` 합, `good_to_fix_count`
  합, `refix_plans_written` 합.
- **defect 밀도** = (static_analysis_failures 합 + must_fix_count 합) /
  loc_added — 1000라인당으로 표시. 정적분석 성분과 리뷰 성분을 별도
  컬럼으로도 병기(어느 축에서 실책이 많은지 구분 가능하게).
- 기존 `--json`/`--since` 옵션과 동일하게 지원.

## 하지 말 것

- review-stats.json 스키마·기록 시점은 건드리지 않는다(issue-41 그대로).
- coding-stats.json을 append-only로 만들지 않는다 — 항상 같은 이슈 번호에
  대해 단일 레코드를 덮어쓰기/병합한다.

## 승인 기준

- [ ] `spec-issue-filenames.md` TYPE enum: `coder-stats` 제거,
      `coding-stats` 추가 + 예시 줄 교체
- [ ] `tdd2` SKILL.md: log-run.sh 언급 0건, Step 5에 자체 카운팅 서술,
      Step 11에 coding-stats.json 최초 생성(스키마·필드) 서술
- [ ] `autotddreview` SKILL.md: Step 3에 coding-stats.json
      read-modify-write(review_outcome 병합) 서술, Step 4 done-check·
      아카이브 목록에 coding-stats.json 포함
- [ ] `log-run.sh`/`.bat`/`.ps1` 파일 삭제 확인
- [ ] `reviewer-scoreboard.py`: coder-stats.jsonl 수집 0건, coding-stats.json
      수집으로 교체, defect 밀도 계산식(정적분석+must_fix)/loc_added 반영,
      단위 테스트 갱신
- [ ] 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-46.sh`:
- SKILL.md 정적 검사 — `log-run` 문자열 0건, coding-stats.json 스키마
  필드명(`static_analysis_failures`, `review_outcome`, `refix_plans_written`
  등) 존재 단언.
- 픽스처 coding-stats.json 2~3건(정적분석만 있는 것 / review_outcome까지
  병합된 것 / static_analysis_failures가 null인 것)으로 스코어보드 실행 —
  coder 섹션에 defect 밀도·정적분석/리뷰 성분 분리 출력, `--json` 유효성
  단언.
- `spec-issue-filenames.md`에 `coder-stats` 잔존 0건, `coding-stats` 존재
  단언.
- pytest 게이트 통과.

## 구현 결과

**구현 완료 일시**: 2026-07-12T22:29:00Z
**변경 파일**:
- `docs/spec/spec-issue-filenames.md` — TYPE enum에 `coding-stats` 추가, `coder-stats` 제거 및 예시 교체
- `.claude/skills/tdd2/SKILL.md` — log-run.sh 제거, 자체 카운터 지시 및 `coding-stats.json` 생성 스펙 추가
- `/home/user1/.claude/skills/tdd2/SKILL.md` — 전역 스킬 동기화
- `.claude/skills/autotddreview/SKILL.md` — `coding-stats.json` 병합 기록 및 아카이브 스펙 반영
- `/home/user1/.claude/skills/autotddreview/SKILL.md` — 전역 스킬 동기화
- `.claude/skills/acpd/defaults/log-run.sh`, `.bat`, `.ps1` — 잔재 파일 삭제
- `tools/reviewer-scoreboard.py` — `coding-stats.json` 기반의 새로운 집계 및 밀도 성분(정적분석/리뷰) 분리 계산 구현
- `tests/test_reviewer_scoreboard_coder.py` — 새 스키마 및 옵션에 맞추어 단위 테스트 갱신
- `regression-tests/verify-issue-45.sh` — 폐기 및 우회 처리
- `regression-tests/verify-issue-45.conflict-with-46.md` — 충돌 문서화
- `regression-tests/verify-issue-46.sh` — 인수 테스트 스크립트 작성

**스펙 이탈**: 없음.

**verify 결과**: `bash regression-tests/verify-issue-46.sh` 22/22 PASS. 전체 회귀 12/12 PASS. `uv run --with pytest pytest tests/` 12/12 PASS.
