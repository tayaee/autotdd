# issue-43: 리뷰어 스코어보드 CLI — review-stats JSON 집계 도구
agent-tier: any

## 배경

issue-20 감사는 리뷰어별 정확도(minimax 92% > gemini 83% > deepseek 70% >
qwen 45%)를 단발로 측정했다. 무인 파이프라인에서 리뷰 사이클이 수백 번
반복되면 이 측정을 상시 지표로 만들 수 있다.

데이터 흐름은 생산·소비로 분리한다: **생산**은 issue-41 — 플래너가
refix-plan을 작성할 때마다 판정 데이터를
`issues/issue-N__TYPE-review-stats.json`으로 기록하고, 아카이브 시 함께
이동한다. **소비**가 본 이슈 — 흩어진 JSON을 모두 모아 스코어보드를
보여주는 Python CLI 도구를 만든다. 플래너는 기록만 하고 집계하지 않으므로
파이프라인에 부담이 없고, 집계 로직의 변경이 파이프라인 재실행을 요구하지
않는다.

**선행**: issue-41 (review-stats JSON 스키마·기록).

## 요구사항

1. **CLI 도구 신설**: `tools/reviewer-scoreboard.py` — Python 3.12,
   표준 라이브러리만 사용(외부 의존성 금지).
2. **입력**: 대상 리포 경로(위치 인자, 생략 시 cwd). `issues/` 및
   `issues/archive/` 전체에서 `*__TYPE-review-stats.json`을 재귀 수집.
   파싱 불가 파일은 건너뛰되 stderr로 경고(침묵 금지).
3. **집계**: 리뷰어(base 모델명)별 —
   - 참여 사이클 수, 총 finding 수
   - must_fix / good_to_fix / gate_rejected / verify_rejected 건수
   - 승격률 = (must_fix + good_to_fix) / findings
4. **출력**:
   - 기본: 사람용 정렬 테이블(승격률 내림차순) + 하단에 해석 가이드
     한 줄(승격률이 지속적으로 낮은 리뷰어는 교체 후보, 표본 적으면 유보).
   - `--json`: 기계용 JSON 출력.
   - `--since YYYY-MM-DD`: 해당 일자 이후 사이클만 집계.
5. **품질**: ruff+pyright 통과, pytest 단위 테스트(픽스처 JSON 수 건으로
   집계·엣지 케이스: 빈 디렉토리, 손상 JSON, 리뷰어 0명).
6. **문서**: cheatsheet.md에 사용법 1줄 추가.

## 승인 기준

- [ ] `tools/reviewer-scoreboard.py` 존재, 표준 라이브러리만 import
- [ ] 대상 리포의 issues/ + archive 재귀 수집, 손상 JSON 경고 후 계속
- [ ] 리뷰어별 집계 필드 5종 + 승격률 출력, `--json`·`--since` 동작
- [ ] pytest 단위 테스트 존재·통과, ruff+pyright 통과
- [ ] cheatsheet.md에 사용법 존재
- [ ] 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-43.sh`: 픽스처 review-stats JSON 2~3건을
임시 디렉토리에 만들어 CLI 실행 — 테이블 출력에 리뷰어명·승격률 존재,
`--json` 출력이 유효 JSON인지 단언. 손상 JSON 1건 섞어 exit 0 + stderr
경고 확인.

## 구현 결과

- **구현 완료 일시**: 2026-07-12T17:22:00-04:00
- **변경 파일**:
  - `tools/reviewer-scoreboard.py` (신규 — stdlib only, 라이브+아카이브 재귀 수집, 리뷰어별 5필드+승격률 집계, 승격률 내림차순 테이블+해석 가이드, `--json`/`--since`, 손상 JSON 경고 후 계속)
  - `tests/test_reviewer_scoreboard.py` (신규 — CLI 프로세스 경계 테스트 6건: 집계·--json·--since·손상 내성·빈 데이터·issues/ 부재)
  - `regression-tests/verify-issue-43.sh` (신규 — 픽스처 JSON 실행 검증 + stdlib 검사 + cheatsheet + pytest 호출)
  - `cheatsheet.md` (사용법 1줄)
- **계획과의 차이**: 이 이슈는 원래 `__STATE-later` 파킹으로 생성되었으나 실행 전 파일명에서 태그가 제거(승격)된 상태였고, 사용자의 명시적 `autotdd 40 41 42 43` 지시에 따라 구현함. 그 외 차이 없음. 참고: 리포에 pyproject.toml이 없어 tdd2의 Python 게이트는 비적용이지만, 이슈 요구대로 ruff(`uvx ruff check`: All checks passed)와 pyright(`uvx pyright`: 0 errors)를 수동 실행해 통과 확인.
- **검증 결과**: pytest 6/6 통과. `verify-issue-43.sh` PASS (테이블·승격률 50.0%·해석 가이드·--json 유효성·--since 필터·손상 JSON exit 0+경고·stdlib-only·cheatsheet). 전체 회귀 스위트 PASS=40 FAIL=0.
