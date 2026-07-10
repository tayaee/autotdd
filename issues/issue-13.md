# issue-13: autoqa 1회형 + 런처 3종

## 배경

사용자가 부르는 qa 롤의 진입점. preflight·뮤텍스로 감싼 error-to-autofix 실행.

## 요구사항

1. `.claude/skills/autoqafix/autoqa.py` 작성 (PEP-723): ① `preflight("qa", cwd)` — 실패 시
   `[원인]`/`[조치]` 전부 출력 + exit 1, ② `acquire_lock("qa")` — 실패 시
   "이미 <role>이 실행 중 (<host>, <start>)" 출력 + exit 3,
   ③ error-to-autofix 실행(같은 디렉토리 모듈로 import 또는 subprocess),
   ④ finally에서 release_lock
2. repo 루트에 `autoqa.sh`, `autoqa.ps1`, `autoqa.bat` 런처 작성:
   - 자신의 위치(`$0`/`%~dp0`) 기준으로 `.claude/skills/autoqafix/autoqa.py`를 찾아
     `uv -q run <절대경로> --repo <현재 cwd>`로 실행 (cwd = 대상 앱 repo 규약)
   - `uv`가 없으면 `[원인] uv 없음` `[조치] curl -LsSf https://astral.sh/uv/install.sh | sh`
     출력 후 exit 127
   - `.bat`: 비정상 종료 시 `pause` (Startup 창 소멸 방지)
3. exit code 규약: 0 정상(보고 0건 포함), 1 preflight 실패, 3 잠금 경합

## 승인 기준

- [ ] 픽스처 repo를 cwd로 `autoqa.sh` 실행(AUTOQAFIX_WRAPPER=fake) → issue-12와
      동일한 결과가 나온다 (원격에 autofix 항목)
- [ ] `logs/` 없는 디렉토리에서 exit 1 + `[원인]`/`[조치]` 출력
- [ ] 잠금 파일을 미리 만들어 두면 exit 3 + 안내 출력
- [ ] `bash -n autoqa.sh` 통과, `.bat`에 `pause` 존재(grep)

## 검증

`regression-tests/verify-issue-13.sh` 작성: 위 전부 자동화.
