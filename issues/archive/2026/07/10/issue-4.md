# issue-4: LLM 래퍼 포팅 — claudecli/minimaxcli
agent-tier: paid-only

## 배경

래퍼 이름은 `<provider>cli` 규약이다 — 감싸는 실제 CLI와의 이름 충돌(자기호출)을
피한다(CONTEXT.md "LLM 래퍼"). 기존 참고 구현이 개인 머신의
`/rosenas/data/util/sonnet.bat`(및 `minimax.bat`)에 있다 — 접근 가능하면 먼저 읽고
동작(환경변수 설정 → `claude --model <M> --effort medium
--permission-mode=bypassPermissions` 호출, `-p` 인자/파일 인자 분기)을 그대로
옮기고, 접근 불가 환경이면 이 이슈의 명세만으로 구현한다.
설계 근거: `docs/autoqafix-design.md`의 "LLM 선정"과 "구현 형태".
신규 3종(codexcli/antigravitycli/deepseekcli)은 issue-5로 분리.

## 요구사항

1. `.claude/skills/autoqafix/wrappers/`에 `claudecli.{sh,ps1,bat}`,
   `minimaxcli.{sh,ps1,bat}` 작성
2. `claudecli.*`: `MODEL=sonnet`, ANTHROPIC 관련 env 초기화 후 `claude` 호출.
   `minimaxcli.*`: claude CLI를 MiniMax 엔드포인트로 돌려 쓴다 — 모델 MiniMax-M3,
   `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`을 env `MINIMAX_API_KEY` 기반으로
   설정(키 미설정 시 `[원인]`/`[조치]` 출력 후 exit 1). 비밀키 하드코딩 금지
3. 인자 규약(공통): 첫 인자가 존재하는 파일이면 그 내용을 stdin으로
   `claude ... -p`에 파이프, 아니면 인자 전체를 그대로 전달
4. 실제 CLI(`claude` 등)는 PATH에서 찾는다. 테스트에서 PATH 앞에 fake를 놓아 대체
   가능해야 한다(절대경로 하드코딩 금지)
5. mitmproxy CA 처리(`NODE_EXTRA_CA_CERTS`가 이미 설정돼 있으면 보존) 반영

## 승인 기준

- [ ] PATH 앞에 `regression-tests/lib/fake-claude.sh`를 `claude`로 심고
      `wrappers/claudecli.sh -p "hi"` 실행 → `FAKE_LOG`에 `--model sonnet`과
      `--permission-mode=bypassPermissions`가 기록된다
- [ ] 파일 인자 모드: 임시 파일 경로를 주면 fake가 stdin으로 그 내용을 받는다
- [ ] `wrappers/minimaxcli.sh -p "hi"` → `FAKE_LOG`에 MiniMax 모델명이 기록된다
- [ ] `.sh` 2종 `bash -n` 통과. `.ps1`은 존재 + 핵심 문자열
      (`--model`, `bypassPermissions`) grep으로 확인(WSL에서 실행 검증 불가함을 주석에 명시)

## 검증

`regression-tests/verify-issue-4.sh` 작성: 승인 기준 전부 자동화 (fake CLI 사용,
크레딧 사용 금지).

## 구현 결과

**구현 완료 일시**: 2026-07-10T17:46:43-0400

**변경 파일**:
- `.claude/skills/autoqafix/wrappers/claudecli.{sh,ps1,bat}` (신규)
- `.claude/skills/autoqafix/wrappers/minimaxcli.{sh,ps1,bat}` (신규)
- `regression-tests/lib/fake-claude.sh` (수정: env `FAKE_STDIN_FILE` 설정 시
  stdin을 파일로 캡처하는 옵션 추가 — 기본 동작은 그대로라 issue-3 회귀 없음)
- `regression-tests/verify-issue-4.sh` (신규)

**계획 대비 편차**: `/rosenas/data/util/sonnet.bat`, `minimax.bat` →
`minimax-claude.bat` → `minimax3-claude.bat` 체인에 실제 접근 가능해 그대로
참고해 이식함. 두 참고 구현이 서로 다른 권한 플래그를 쓰고 있어(`sonnet.bat`은
`--permission-mode=bypassPermissions`, `minimax3-claude.bat`은
`--dangerously-skip-permissions`) 이슈 본문의 승인 기준에 맞춰 각각 원본
그대로 유지했다(통일하지 않음). `NODE_EXTRA_CA_CERTS` "이미 설정돼 있으면
보존" 요구사항은 원본 `minimax3-claude.bat`(항상 덮어씀)과 다르게 구현했다 —
요구사항 5가 명시적으로 우선.

**검증 결과**: `regression-tests/verify-issue-4.sh` 단독 실행 exit 0(승인
기준 전부 PASS). `run-regression-tests`로 issue-3+issue-4 회귀 스위트 전체
실행 결과 PASS=2 FAIL=0. Python 프로젝트가 아니므로(`pyproject.toml` 없음)
ruff/pyright/pytest 단계는 해당 없음. `.ps1`은 WSL 환경에 PowerShell이 없어
실행 검증 불가 — 존재 확인과 핵심 문자열(`--model`, `bypassPermissions`)
grep으로만 확인함(스크립트 상단 주석에도 명시).
