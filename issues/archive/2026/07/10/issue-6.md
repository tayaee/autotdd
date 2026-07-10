# issue-6: qwencli 래퍼 3종
agent-tier: local-ok

## 배경

로컬 무료 LLM용 래퍼. 내부에서 `qwen`(qwen.exe)을 호출하므로 자기호출 충돌을 피해
이름은 `qwencli`다(`qwen.{bat,ps1,sh}` 금지 — CONTEXT.md "LLM 래퍼" 참조).

## 요구사항

1. `.claude/skills/autoqafix/wrappers/`에 `qwencli.sh`, `qwencli.ps1`,
   `qwencli.bat` 작성
2. 동작: 받은 인자를 그대로 `qwen`에 전달 (`qwen -p PROMPT` 형태 지원).
   `qwen`은 PATH에서 찾는다(하드코딩 금지)
3. claudecli/minimaxcli와 동일한 인자 규약: 첫 인자가 존재하는 파일이면 내용을 stdin으로
   `qwen -p`에 파이프
4. `qwen`이 PATH에 없으면 `[원인] qwen CLI가 PATH에 없음` + `[조치] qwen 설치 또는
   PATH 추가` 출력 후 exit 127

## 승인 기준

- [ ] PATH 앞에 `fake-qwen.sh`를 `qwen`으로 심고 `wrappers/qwencli.sh -p "hi"` →
      `FAKE_LOG`에 `-p hi`가 기록되고 exit 0
- [ ] `qwen`이 PATH에 없는 환경에서 exit 127 + `[원인]`/`[조치]` 두 줄 출력
- [ ] `bash -n qwencli.sh` 통과, `.bat`/`.ps1`은 존재 + `qwen` 호출 grep 확인

## 검증

`regression-tests/verify-issue-6.sh` 작성: 승인 기준 자동화 (fake-qwen 사용).

## 구현 결과

**구현 완료 일시**: 2026-07-10T17:54:10-0400

**변경 파일**:
- `.claude/skills/autoqafix/wrappers/qwencli.{sh,ps1,bat}` (신규)
- `regression-tests/lib/fake-qwen.sh` (수정: env `FAKE_STDIN_FILE` 설정 시
  stdin을 파일로 캡처하는 옵션 추가 — 기본 동작은 그대로라 issue-3 회귀 없음.
  issue-4에서 fake-claude.sh에 추가한 것과 동일한 패턴)
- `regression-tests/verify-issue-6.sh` (신규)

**계획 대비 편차**: 요구사항 3(파일 인자 → stdin 파이프)은 승인 기준 목록에
별도 항목으로 없었지만 명시적 요구사항이라 구현하고 회귀 테스트에도 포함시켰다.

**검증 결과**: `regression-tests/verify-issue-6.sh` 단독 실행 exit 0(승인
기준 전부 PASS). `run-regression-tests`로 issue-3+4+5+6 전체 실행 결과
PASS=4 FAIL=0. Python 프로젝트가 아니므로(`pyproject.toml` 없음)
ruff/pyright/pytest 단계는 해당 없음. `.ps1`/`.bat`은 실 `qwen` CLI와
PowerShell이 모두 이 환경에 없어 실행 검증 불가 — 존재 확인과 `qwen` 문자열
grep으로만 확인함.
