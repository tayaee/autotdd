# issue-5: 신규 래퍼 3종 — codexcli / antigravitycli / deepseekcli
agent-tier: local-ok

## 배경

issue-4에서 분리된 신규 래퍼 3종. 인자 규약은 issue-4의 claudecli/minimaxcli와
동일하다(CONTEXT.md "LLM 래퍼"). 대응 CLI(`codex`/`antigravity`/`deepseek`)는 이
개발 환경에 설치돼 있지 않을 수 있으므로 **`--help` 조사를 요구하지 않는다** —
아래 명세의 단순 pass-through로 구현하고, 플래그가 미검증임을 주석으로 남긴다.

## 요구사항

1. `.claude/skills/autoqafix/wrappers/`에 `codexcli.{sh,ps1,bat}`,
   `antigravitycli.{sh,ps1,bat}`, `deepseekcli.{sh,ps1,bat}` 작성 (9개 파일)
2. 동작: 받은 인자를 그대로 PATH의 대응 CLI(`codex`/`antigravity`/`deepseek`)에
   전달 (`-p PROMPT` 형태 지원). 절대경로 하드코딩 금지
3. issue-4와 동일한 인자 규약: 첫 인자가 존재하는 파일이면 그 내용을 stdin으로
   `<CLI> -p`에 파이프, 아니면 인자 전체를 그대로 전달
4. 대응 CLI가 PATH에 없으면 `[원인] <CLI>가 PATH에 없음` + `[조치] <CLI> 설치
   또는 PATH 추가` 출력 후 exit 127
5. 각 래퍼 상단 주석: "플래그는 미검증 — 실 CLI 설치 환경에서 `--help`로 확인 후
   조정할 것"

## 승인 기준

- [ ] `regression-tests/lib/fake-claude.sh`를 `codex`/`antigravity`/`deepseek`
      이름으로 PATH 앞에 복사해 두고 각 `.sh` 래퍼를 `-p "hi"`로 실행 →
      `FAKE_LOG`에 `-p hi`가 기록되고 exit 0
- [ ] 파일 인자 모드: 임시 파일 경로를 주면 fake가 stdin으로 그 내용을 받는다
- [ ] 대응 CLI가 PATH에 없는 환경에서 exit 127 + `[원인]`/`[조치]` 두 줄 출력
- [ ] `.sh` 3종 `bash -n` 통과, `.ps1`/`.bat`은 존재 + 대응 CLI명 grep 확인

## 검증

`regression-tests/verify-issue-5.sh` 작성: 승인 기준 자동화 (fake CLI 사용,
크레딧 사용 금지).

## 구현 결과

**구현 완료 일시**: 2026-07-10T17:50:28-0400

**변경 파일**:
- `.claude/skills/autoqafix/wrappers/codexcli.{sh,ps1,bat}` (신규)
- `.claude/skills/autoqafix/wrappers/antigravitycli.{sh,ps1,bat}` (신규)
- `.claude/skills/autoqafix/wrappers/deepseekcli.{sh,ps1,bat}` (신규)
- `regression-tests/verify-issue-5.sh` (신규)

**계획 대비 편차**: 없음. 세 래퍼 모두 issue-4와 동일한 인자 규약(첫 인자가
파일이면 stdin 파이프, 아니면 그대로 전달)을 공유하며, 대응 CLI가 PATH에
없으면 `[원인]`/`[조치]` 출력 후 exit 127. 명세대로 `--help` 조사는 하지
않았고 각 파일 상단에 "플래그 미검증" 주석을 남겼다.

**검증 결과**: `regression-tests/verify-issue-5.sh` 단독 실행 exit 0(승인
기준 전부 PASS). `run-regression-tests`로 issue-3+4+5 전체 실행 결과
PASS=3 FAIL=0. Python 프로젝트가 아니므로(`pyproject.toml` 없음)
ruff/pyright/pytest 단계는 해당 없음. `.ps1`/`.bat`은 실 CLI와 PowerShell이
모두 이 환경에 없어 실행 검증 불가 — 존재 확인과 CLI명 grep으로만 확인함.
