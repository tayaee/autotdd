# issue-12: 로그 스캐너 — 오프셋, 에러 추출, 빈도 랭킹
agent-tier: paid-only

## 배경

autoqa의 결정적 심장부. LLM 없이 완전히 동작해야 한다. 명세:
`docs/autoqafix-design.md`의 "autoqa" 1~3번과 "항목 파일에 들어가는 기계 판독 줄"의
dedup-key 규칙.

## 요구사항

1. `.claude/skills/autoqafix/log-scan.py` 작성 (PEP-723). CLI:
   `uv -q run .claude/skills/autoqafix/log-scan.py --repo <path> [--state-dir <path>] [--dry-run]`
   → stdout에 JSON: `{"errors":[{"dedup_key":..., "count":..., "excerpt":...,
   "latest_ts":..., "logfile":...}, ...], "window":{"start":...,"end":...}}`
   (count 내림차순, 최대 100개)
2. 대상: `<repo>/logs/*.log`만 (`.jsonl`, `.log.1` 등 제외)
3. 오프셋 상태 `<state-dir>/offsets.json` (기본 state-dir는
   `autoqafix_core.state_dir()`): 파일별 `{prefix_sha1, prefix_len, size, offset}`
   - 첫 관측 파일: offset=EOF로 기록만 하고 이번 스캔에서 제외
   - prefix 불일치 또는 size<offset → 새 파일로 간주, offset 0부터
   - 새 구간이 10MB 초과 시 마지막 10MB만 (건너뛴 바이트 수를 stderr에 경고)
   - `--dry-run`이면 offsets.json을 갱신하지 않는다 (연기 = dry-run 후 미커밋)
4. 추출: ① `Traceback (most recent call last):`부터 예외 라인까지의 블록,
   ② `[ERROR]`/`[CRITICAL]` 라인. `[WARNING]`/`[INFO]` 무시
5. dedup_key 계산 — 설계 문서 규칙 그대로:
   - traceback: repo 내부 경로(절대경로가 repo 하위이거나 상대경로가 repo에
     존재)인 가장 깊은 프레임의 `tb:<상대경로>:<라인>:<예외타입>`
   - 그 외: `line:<로그파일명>:<로거명>:<정규화해시8>` (숫자열→`#`, 따옴표 내용
     제거, 공백 축약 후 sha1 앞 8자)
6. excerpt: 해당 key의 **가장 최근** 발생 지점 앞 10줄 + 블록/라인 자체 + 뒤 10줄,
   16KB 초과 시 뒤에서 절단하고 `...[truncated]` 표시
7. latest_ts: 발생 라인(traceback은 직전 타임스탬프 라인)의 타임스탬프 문자열

## 승인 기준

픽스처 로그(issue-3)를 기준으로:

- [ ] 첫 실행(첫 관측)은 `errors:[]` — EOF 초기화 확인
- [ ] 로그에 새 라인들을 append한 뒤 재실행 → traceback key(count=추가한 반복
      수)와 ERROR line key가 count 내림차순으로 나온다
- [ ] WARNING만 append하면 `errors:[]`
- [ ] 파일을 truncate 후 새 내용 기록 → 새 파일로 감지, 전체 재스캔
- [ ] `--dry-run` 2회 연속 실행의 출력이 동일하다 (오프셋 비전진)
- [ ] excerpt에 traceback 전체와 전후 10줄이 포함된다

## 검증

`regression-tests/verify-issue-12.sh` 작성: 위 시나리오 전부. jq 사용 가능.
