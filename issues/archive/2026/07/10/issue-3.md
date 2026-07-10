# issue-3: 테스트 인프라 — 픽스처 repo 생성기와 fake 도구들
agent-tier: paid-only

## 배경

issue-4 ~ issue-20의 모든 검증은 실제 LLM 크레딧을 쓰지 않아야 한다. 이를 위한
공용 테스트 도구를 먼저 만든다. 설계 근거: `docs/autoqafix-design.md`.

## 요구사항

1. `regression-tests/lib/make-fixture-repo.sh` 작성. 실행하면 임시 디렉토리에
   다음을 만들고 그 경로를 stdout 마지막 줄에 출력한다:
   - bare 원격 repo(`origin.git`)와 그 클론(`work/`) — user.name/email 로컬 설정 포함
   - `work/issues/` (빈 디렉토리 아님: `.gitkeep`), `work/logs/`
   - `work/logs/app.main.log`: Python logging 포맷
     (`2026-07-10 12:00:00,000 [LEVEL] logger.name - message`) 라인 30개 이상.
     반드시 포함: ① 동일 traceback 블록(`Traceback (most recent call last):` ...
     `ValueError: bad value`, 프레임에 `work/src/app.py", line 42`) 5회 반복,
     ② `[ERROR]` 단독 라인 3회(동일 메시지, 숫자만 다름), ③ `[WARNING]` 라인 2회,
     ④ `[INFO]` 라인 다수
   - `work/src/app.py` 더미 파일(50줄 이상, 42번째 줄 존재), 초기 commit + push
2. `regression-tests/lib/fake-wrapper.sh` 작성: `claudecli`/`minimaxcli`/`qwencli`
   등 래퍼 대역.
   `-p PROMPT`를 받으며 동작은 env `FAKE_MODE`로 제어:
   - `ok`(기본): `FAKE_OUTPUT_FILE`이 있으면 그 내용을 stdout에 출력, 없으면 `pong`
   - `fail`: stderr에 메시지, exit 1
   - `hang`: 600초 sleep
   - `archive`: cwd의 git repo에서 env `FAKE_TARGET`이 가리키는 issues/ 파일을
     `issues/archive/2026/07/10/`로 `git mv` + commit + push (autotdd 성공 모사)
   호출된 인자 전체를 `FAKE_LOG` 파일에 한 줄 append(호출 검증용)
3. `regression-tests/lib/fake-claude.sh`, `fake-qwen.sh` 작성: 실 CLI 대역.
   받은 인자 전부를 `FAKE_LOG`에 기록하고 `pong` 출력 후 exit 0
4. 모두 실행 권한(`chmod +x`), bash 문법(`bash -n`) 통과

## 승인 기준

- [ ] `make-fixture-repo.sh` 2회 실행 시 서로 독립된 경로 2개가 나온다
- [ ] 픽스처의 `git -C work log --oneline`이 1개 이상 커밋을 보여준다
- [ ] `FAKE_MODE=archive FAKE_TARGET=issues/autofix-1.md fake-wrapper.sh -p x`가
      (해당 파일을 미리 만들어 둔 픽스처에서) 파일을 archive로 옮기고 push한다
- [ ] `FAKE_MODE=fail`이 exit 1, `ok`가 exit 0

## 검증

`regression-tests/verify-issue-3.sh` 작성: 위 승인 기준 4개를 그대로 자동화.
임시 디렉토리는 trap으로 정리. 공용 헬퍼가 필요하면 `regression-tests/lib/`에 둔다.

## 구현 결과

**구현 완료 일시**: 2026-07-10T17:39:03-0400

**변경 파일**:
- `regression-tests/lib/make-fixture-repo.sh` (신규)
- `regression-tests/lib/fake-wrapper.sh` (신규)
- `regression-tests/lib/fake-claude.sh` (신규)
- `regression-tests/lib/fake-qwen.sh` (신규)
- `regression-tests/verify-issue-3.sh` (신규)

**계획 대비 편차**: 없음. 단, `fake-wrapper.sh`의 `archive` 모드에서
`git push`가 로컬 브랜치와 원격 브랜치 이름 불일치로 거부되는 문제가 있어
`make-fixture-repo.sh`가 초기 커밋 후 로컬 브랜치를 `main`으로 명명(`git
branch -M main`)하도록 했다. 승인 기준의 archive 대상 경로
`issues/archive/2026/07/10/`는 `date +%Y/%m/%d`로 동적 계산했다(픽스처 로그의
날짜, 그리고 오늘 날짜와 실제로 일치).

**검증 결과**: `regression-tests/verify-issue-3.sh` 단독 실행 exit 0(승인
기준 4개 모두 PASS). 이 이슈가 저장소의 첫 회귀 스크립트이므로
`run-regression-tests` 전체 스위트 결과는 이 스크립트 하나로 구성됨 — 통과.
Python 프로젝트가 아니므로(`pyproject.toml` 없음) ruff/pyright/pytest 단계는
해당 없음.
