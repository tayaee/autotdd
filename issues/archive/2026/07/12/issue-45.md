# issue-45: coder-stats — 구현자 축 정량화 (log-run 래퍼 + LOC + 스코어보드 coder 축)
agent-tier: any

## 배경

2026-07-12 그릴링 2차에서 "어느 모델이 기초 코딩 실력이 부족한지 감지"
요구가 나와, 같은 날 오전의 "coder 기록 안 함" 결정을 번복했다. 확정된
설계 결정 (CONTEXT.md "coder 실수"·"defect 밀도" 용어 참조).

- **coder 식별 기록**: 실행 세션이 자기 base명+버전 포함 모델명을 기록.
- **실수 = 정적분석 감지만**: ruff fix 수·pyright 에러 수. **pytest
  실패는 기록하지 않는다** (TDD red는 의도된 실패, green 과정의 실패도
  실수로 세지 않기로 확정). SyntaxError(ruff E999)는 "기초 실수"로 별도
  카운터 분리 — 어느 모델이 컴파일도 안 되는 코드를 내는지 탐지.
- **측정 지점 = 로깅 래퍼**: 평가받는 모델의 자기 보고 금지. run-*
  스크립트 호출을 래퍼가 감싸 출력 파싱으로 기계 기록. 프로젝트
  override 스크립트도 동일하게 계측된다.
- **LOC = 시작HEAD..완료HEAD 전 파일 added 합** (git numstat, 삭제 제외,
  바이너리 제외). defect 밀도의 분모.
- **기록 = 단일 JSONL** append-only, **집계 = CLI** (생산/소비 분리,
  review-stats와 동일 철학).
- **집계는 합산 + run 횟수 병기**: 반복 run의 중복 감지는 걸러내지 않고
  단순 합산하되 run 횟수를 항상 병기 (churn도 실력 신호). 정책 변경은
  원시 JSONL이 있으므로 CLI에서 언제든 가능.

**선행**: issue-43 (스코어보드 CLI). issue-44와 독립 (파일 다름).

## 요구사항

1. **log-run 래퍼 신설**: `.claude/skills/aacpd/defaults/log-run.sh`
   (bat/ps1 동반, 기존 defaults와 동일 3종 세트).
   사용법: `log-run.sh <이슈번호> <tool명> <실제 스크립트> [인자...]`
   - 실제 스크립트를 실행하고 stdout/stderr는 그대로 통과(투명 래퍼),
     exit code도 그대로 전파.
   - 출력을 파싱해 `issues/issue-<N>__TYPE-coder-stats.jsonl`에 한 줄
     append: `{"kind":"run","ts":<ISO8601>,"tool":<tool명>,
     "exit":<code>,"errors":<수>,"fixed":<수>,"syntax_errors":<수>}`
   - 파싱 규칙 (도구 표준 출력 기준, 플래그 변경 불요):
     - ruff: `Found N errors (M fixed, ...)` / `Fixed M errors` 계열에서
       errors·fixed 추출, `E999` 발생 줄 수 → syntax_errors.
     - pyright: 말미 `X errors, Y warnings ...`에서 X → errors.
     - 파싱 실패 시 errors 등을 `null`로 기록하되 라인은 남긴다(침묵
       금지).
2. **계측 대상은 정적분석만**: tdd2가 `run-ruff`/`run-pyright`/
   `run-pyright-full`을 호출할 때 log-run 경유를 의무화.
   `run-unit-tests`/`run-regression-tests`/red 단계 직접 pytest는
   **계측하지 않는다** (기록 자체를 안 함).
3. **tdd2 SKILL.md 스펙 변경**:
   - 시작 시 `git rev-parse HEAD`를 `<시작HEAD>`로 기록 (autotddreviewfix
     Step 1과 동일 관행을 tdd2 자체로 내림).
   - 정적분석 3종 호출을 log-run 경유로 명시.
   - 구현 결과 갱신 시점에 summary 라인 append:
     `{"kind":"summary","ts":...,"coder":<base명>,"model":<버전 포함
     모델명>,"loc_added":<시작HEAD..HEAD 전 파일 numstat added 합>}`
     — loc_added는 git에서 기계 산출(삭제·바이너리 제외).
4. **파일명 규약 반영**: `docs/spec/spec-issue-filenames.md`의 TYPE
   enum에 `coder-stats` 추가.
5. **아카이브 동선**: aacpd 스펙에 `issue-N__TYPE-coder-stats.jsonl`을
   이슈 파일과 함께 아카이브하도록 추가 (autotddreviewfix Step 4의 TYPE
   파일 아카이브 목록에도 포함).
6. **스코어보드 coder 축**: `tools/reviewer-scoreboard.py` 확장 —
   coder-stats.jsonl을 라이브+아카이브 재귀 수집, coder(model)별:
   - 이슈 수, run 횟수, loc_added 합
   - errors 합, fixed 합, syntax_errors 합
   - **defect 밀도** = (errors+fixed 합) / loc_added — 1000라인당으로
     표시, syntax_errors는 별도 컬럼(기초 실수 지표)
   - 기존 리뷰어 테이블과 별도 섹션으로 출력, `--json`·`--since` 동일
     지원. 손상 라인은 경고 후 계속(침묵 금지).
7. **품질**: 래퍼는 bash 표준 도구만, CLI는 표준 라이브러리만.
   ruff+pyright+pytest 통과, 파서·집계 단위 테스트(픽스처: ruff/pyright
   실제 출력 샘플, 파싱 불가 출력, 빈 JSONL, summary 없는 JSONL).

## 승인 기준

- [ ] log-run.sh(+bat/ps1) 존재 — 투명 통과·exit 전파·JSONL append,
      ruff/pyright 출력 파싱, 파싱 실패 시 null 기록
- [ ] tdd2 SKILL.md에 시작HEAD 기록·log-run 경유·summary append 명시,
      pytest/회귀는 계측 제외 명시
- [ ] spec-issue-filenames.md TYPE enum에 coder-stats 존재
- [ ] aacpd·autotddreviewfix 스펙에 coder-stats.jsonl 아카이브 동선 존재
- [ ] 스코어보드에 coder 섹션(defect 밀도/1000라인, syntax 별도,
      run 횟수 병기), `--json`·`--since` 동작
- [ ] 단위 테스트 존재·통과, ruff+pyright 통과, 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-45.sh`:
- ruff/pyright 출력 샘플을 흉내낸 가짜 스크립트를 log-run으로 실행 —
  JSONL에 run 라인 생성, errors/fixed/syntax_errors 수치 단언, exit
  code 전파 단언.
- summary 라인 포함 픽스처 JSONL로 스코어보드 실행 — coder 섹션에
  모델명·defect 밀도 출력, `--json` 유효성 단언.
- SKILL.md·spec 문구 grep 단언.

## 구현 결과

**구현 완료 일시**: 2026-07-12T00:00:00Z
**변경 파일**:
- `.claude/skills/aacpd/defaults/log-run.sh` — 신규 (sh 버전; ruff/pyright 파싱, JSONL append, exit 전파, parse-failure → null)
- `.claude/skills/aacpd/defaults/log-run.ps1` — 신규 (PowerShell 포트, 동일 규칙)
- `.claude/skills/aacpd/defaults/log-run.bat` — 신규 (pwsh/powershell 디스패처)
- `.claude/skills/tdd2/SKILL.md` — Step 5에 log-run 경유·시작HEAD·pytest 비계측, Step 11에 summary 라인 append 스펙 추가
- `.claude/skills/autotddreviewfix/SKILL.md` — Step 4 done check·아카이브 목록에 `coder-stats.jsonl` 추가
- `docs/spec/spec-issue-filenames.md` — TYPE enum에 `coder-stats` 추가, 산출물 예시 한 줄 추가
- `tools/reviewer-scoreboard.py` — coder 섹션 (defect_density_per_kloc, syntax 별도, run 횟수, `--json`/`--since` 지원), collect_coders 함수 추가. `re` 미사용 — stdlib allowlist 호환
- `tests/test_reviewer_scoreboard_coder.py` — 신규 9건 (집계·밀도·syntax 분리·run 횟수·since·손상 라인·고아 run·summary 필드 검증·다중 summary 누적)
- `regression-tests/verify-issue-45.sh` — 신규. 27개 단언 (스펙/TYPE enum, SKILL.md 4문서, log-run.sh 11케이스, scoreboard 3픽스처, pytest 게이트)
- `CONTEXT.md` — `coder 실수`·`defect 밀도` 용어 항목 추가

**스펙 이탈**: 없음. log-run은 ruff/pyright만 계측 (pytest/회귀 비계측 — spec 그대로).

**verify 결과**: `bash regression-tests/verify-issue-45.sh` 27/27 PASS. 전체 회귀 42/42 PASS. `uv run --with pytest pytest -q tests/` 17/17 PASS. `python -m compileall` 클린.
