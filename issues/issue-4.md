# issue-4: LLM 래퍼 패밀리 — claudecli/minimaxcli 포팅 + codexcli/antigravitycli/deepseekcli 신규

## 배경

래퍼 이름은 `<provider>cli` 규약이다 — 감싸는 실제 CLI와의 이름 충돌(자기호출)을
피한다(CONTEXT.md "LLM 래퍼"). 기존 참고 구현이 개인 머신의
`/rosenas/data/util/sonnet.bat`(및 `minimax.bat`)에 있다 — 접근 가능하면 먼저 읽고
동작(환경변수 설정 → `claude --model <M> --effort medium
--permission-mode=bypassPermissions` 호출, `-p` 인자/파일 인자 분기)을 그대로
옮기고, 접근 불가 환경이면 이 이슈의 명세만으로 구현한다.
설계 근거: `docs/autoqafix-design.md`의 "LLM 선정"과 "구현 형태".

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
6. 신규 3종 `codexcli.{sh,ps1,bat}`, `antigravitycli.{sh,ps1,bat}`,
   `deepseekcli.{sh,ps1,bat}`: 같은 인자 규약으로 각각 PATH의 `codex`,
   `antigravity`, `deepseek` CLI에 `-p PROMPT`를 매핑(각 CLI의 정확한 플래그는
   구현 시 `--help`로 확인하고 주석으로 남김). 대응 CLI가 PATH에 없으면
   `[원인] <CLI>가 PATH에 없음` + `[조치]` 출력 후 exit 127

## 승인 기준

- [ ] PATH 앞에 `regression-tests/lib/fake-claude.sh`를 `claude`로 심고
      `wrappers/claudecli.sh -p "hi"` 실행 → `FAKE_LOG`에 `--model sonnet`과
      `--permission-mode=bypassPermissions`가 기록된다
- [ ] 파일 인자 모드: 임시 파일 경로를 주면 fake가 stdin으로 그 내용을 받는다
- [ ] `wrappers/minimaxcli.sh -p "hi"` → `FAKE_LOG`에 MiniMax 모델명이 기록된다
- [ ] 신규 3종 `.sh`: 대응 CLI가 PATH에 없으면 exit 127 + `[원인]`/`[조치]`,
      fake를 PATH에 심으면 exit 0
- [ ] `.sh` 5종 `bash -n` 통과. `.ps1`은 존재 + 핵심 문자열
      (`--model`, `bypassPermissions`) grep으로 확인(WSL에서 실행 검증 불가함을 주석에 명시)

## 검증

`regression-tests/verify-issue-4.sh` 작성: 승인 기준 전부 자동화 (fake CLI 사용,
크레딧 사용 금지).
