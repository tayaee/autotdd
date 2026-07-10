# autoqafix 설계 명세 (공유 문서)

issue-3 ~ issue-20의 공통 설계 근거. 각 이슈는 이 문서와 `CONTEXT.md`(용어)를 따른다.
용어가 충돌하면 `CONTEXT.md`가 이긴다.

## 목적

다수 앱의 dev 환경(Windows 머신들 + WSL 로컬 개발 머신)에서 무인 자동 개발/수정 루프를
돌린다. 롤 3개: **qa**(로그→결함 보고), **fix**(autofix 스트림 구현), **dev**(issue
스트림 구현). 사람이 repo마다 루프를 골라 구성한다(루프 1개 = repo 1개, cwd = 대상 repo
루트).

## 스트림과 파일 상태

- 사람 스트림: `issues/issue-#.md`, commit 접두사 `issue-#:`
- agent 스트림: `issues/autofix-#.md`, commit 접두사 `autofix-#:`
- 번호는 스트림별 독립, 접미사 불문 스트림 내 유일
- 상태 접미사: 없음(기계 대상) / `-manual`(사람 몫 판정) / `-agent-failed`(실패 대기) /
  `-later`(사람이 미룸). 전이는 rename + commit + push

## 항목 파일에 들어가는 기계 판독 줄

```
# autofix-N: <한 줄 요약>
reported-by: error-to-autofix@<hostname> <ISO8601>
dedup-key: <아래 규칙>
agent-tier: local-ok | paid-only | manual
frequency: <횟수> (<구간 시작> ~ <구간 끝>)
```

- dedup-key 규칙: traceback이면 `tb:<repo 내 최심 프레임 상대경로>:<라인>:<예외타입>`,
  traceback 없는 ERROR/CRITICAL 라인이면 `line:<로그파일명>:<로거명>:<정규화해시8>`
  (정규화: 연속 숫자→`#`, 따옴표 안 내용 제거, 공백 축약; 해시8 = sha1 hex 앞 8자)
- 본문에 지시문 포함: "로그 원문(logs/)을 열지 말 것 — 필요한 발췌는 이 문서에 포함됨"

## LLM 선정

- 후보 래퍼와 유료/로컬 분류는 env `AUTOQAFIX_WRAPPERS`가 선언:
  `"<래퍼명>:paid|local,..."` 꼴, 나열 순서가 우선순위(동률 시 앞쪽).
  기본값 `claudecli:paid,minimaxcli:paid,qwencli:local`
- 래퍼마다 usage 스크립트가 `usage-<래퍼명>.py` 규약으로 짝을 이룸. JSON 한 줄 출력:
  `{"provider":..., "five_hour_remaining_pct":..., "weekly_remaining_pct":...,
  "effective_remaining_pct":..., "available":true|false}`. usage 스크립트가 없는
  래퍼는 후보에서 제외하고 stderr에 경고
- 유효 잔여율 = min(5h, 주간). 유료 중 유효 잔여율 ≥ 50만 적격, 적격이 여럿이면 큰 쪽
  (동률이면 목록 앞쪽). 유료 부적격 → 로컬 중 `available` 첫 번째. 전부 불가 →
  해당 주기 LLM 작업 건너뜀(autoqa는 오프셋 비전진 연기)
- 산출물은 래퍼 이름(예: `claudecli` | `minimaxcli` | `qwencli`). 항목 하나 처리할
  때마다 재선정
- agent-tier 매칭: 로컬 래퍼 선정 시 `local-ok`만, 유료 선정 시 `local-ok`+`paid-only`

## autoqa (보고)

1. `logs/*.log`만 대상 (`.jsonl`, `.log.1` 제외). WARNING 제외, traceback 블록 +
   `[ERROR]`/`[CRITICAL]` 라인만
2. 오프셋 증분 읽기: `~/.cache/autoqafix/<클론ID>/offsets.json`
   (클론ID = sha1(절대경로) 앞 12자). 항목: prefix_hash(첫 1KB, 해시한 길이 포함),
   size, offset. 해시 불일치 또는 size<offset → 새 파일, 오프셋 0. 첫 관측 파일은
   EOF에서 시작. 사이클당 새 구간 10MB 초과 시 마지막 10MB만
3. 새 구간에서 dedup-key별 빈도 집계(상위 100) → 미보고(미결 항목의 dedup-key에 없는
   것) 최빈 5개만 보고. 발췌 = 최신 발생 앞뒤 10줄(+traceback 전체), 항목당 16KB 상한
4. 본문·제목·agent-tier는 선정된 유료 래퍼가 작성(유료 부적격이면 연기)
5. 번호 예약: 1) `issues/**`(archive 포함) + `regression-tests/verify-*-*.sh`에서
   스트림별 최대 번호+1, 2) 첫 줄 요약 + reported-by 줄만 있는 파일 commit+push,
   3) push 거부 → 예약 커밋 제거, pull --rebase, 다음 번호 재시도, 4) 성공 후 본문
   채워 두 번째 commit+push
6. dedup은 git이 원본: 보고 전 `issues/` 미결 항목(접미사 포함, archive 제외)에서
   dedup-key 검색. `## ` 본문 섹션 없는 파일 = 예약 중, 건너뜀

## autofix / autodev (구현)

1. 전용 agent worktree(`~/.cache/autoqafix/<클론ID>/worktree`, main 추적)에서만 git
   조작. 사람 main tree는 절대 건드리지 않음
2. pull → 접미사 없는 항목 열거(오름차순) → 항목마다 LLM 재선정 → agent-tier 매칭 →
   `<래퍼> -p "/autotdd <id> worktree"` (구현 타임아웃 3시간, 초과 시 트리 강제 종료)
3. 스탬프 없는 항목(사람 작성)은 유료 래퍼가 1회 tier 판정 후 스탬프 줄 추가 commit.
   `manual` 판정 → `-manual` rename+push
4. 성공 판정 = 항목 파일이 archive로 이동했는가(pull 후 확인). 실패/타임아웃 →
   `## agent 실패 기록`에 `- <ISO8601> <래퍼>: <요지>` 추가 → `-agent-failed`
   rename → 해당 파일만 add·commit·push → 다음 항목. 승급 없음, 정체는 사람 개입
5. autodev = 같은 엔진, `--stream issue` (issue-#.md 담당)

## 루프

- 1회형이 핵심 단위: `autoqa` `autofix` `autodev` `autoqafix`(qa→fix 1회씩).
  루프형은 반복 껍데기. 페이즈별 최소 간격 6시간(마지막 실행 시각을 `~/.cache`에 기록)
- `autoqafix-loop`: 시작 시 3분 대기(부팅 직후 로그 생산 대기) 후 1라운드.
  `--reboot-on-fix`: 라운드에서 1개 이상 완료 시 `shutdown /r /t 60`(SHUTDOWN_CMD로
  주입 가능). 폭주 가드: 24시간 내 4회 초과 시 reboot 보류·경고 후 지속
- 뮤텍스: `<repo>/.git/autoqafix.lock` (host/pid/role/start). agent끼리만 직렬화,
  4시간 초과 잠금은 부실로 회수. 후발 주자는 안내 출력 후 종료

## 구현 형태

- 로직은 Python 한 벌(PEP-723 인라인 메타데이터, `uv -q run`), 원본 위치는
  `.claude/skills/autoqafix/`(스킬 폴더 = 배포 단위 — 스킬 설치만으로 엔진이 따라감).
  `.bat`/`.ps1`/`.sh`는 repo 루트의 얇은 shim(자기 위치 기준으로 스킬 폴더의 엔진
  호출). `.bat`은 에러 시 `pause`
- LLM 래퍼는 `.claude/skills/autoqafix/wrappers/`에 번들:
  `{claudecli,minimaxcli,qwencli,codexcli,antigravitycli,deepseekcli}.{sh,ps1,bat}` +
  짝 `ping-*` 진단. 래퍼가 감싸는 실제 CLI(`claude`, `qwen` 등)는 PATH 전제.
  usage 스크립트는 실사용 3종(claudecli/minimaxcli/qwencli)만 엔진 폴더에 제공.
  엔진의 래퍼 해석 순서: `AUTOQAFIX_WRAPPER_DIR` env → 자기 옆 `wrappers/` → PATH
- 모든 진입점은 preflight 수행, 실패 항목마다 `[원인]`+`[조치]` 짝 출력
- 환경변수(테스트 주입점): `AUTOQAFIX_IMPL_TIMEOUT`(기본 10800초),
  `AUTOQAFIX_LIGHT_TIMEOUT`(1200초), `AUTOQAFIX_INTERVAL`(21600초),
  `AUTOQAFIX_BOOT_WAIT`(180초), `AUTOQAFIX_MAX_REBOOTS_24H`(4), `SHUTDOWN_CMD`,
  `AUTOQAFIX_WRAPPER`(래퍼 강제 지정), `AUTOQAFIX_WRAPPERS`(후보·분류 목록),
  `AUTOQAFIX_WRAPPER_DIR`(래퍼 디렉토리 대체),
  `AUTOQAFIX_USAGE_CMD_<래퍼명 대문자>`(usage 스크립트 대체)
- 검증은 크레딧 제로: `regression-tests/lib/`의 fake 래퍼·픽스처 repo 생성기만 사용.
  실 LLM 확인은 사람이 `ping-*`으로

## 사용 방식 3가지

1. Claude Code 스킬 트리거: `/autoqa` `/autofix` `/autodev` `/autoqafix` — 1회형 실행
   (스킬 설치만으로 동작 — 엔진이 스킬 폴더에 동봉)
2. production(Windows): autotdd 클론 후 Startup에 지름길("시작 위치" = 대상 앱 repo)
3. WSL 로컬 개발 머신: 클론의 `*.sh` 수동 호출
