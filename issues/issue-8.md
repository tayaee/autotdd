# issue-8: usage 스크립트 3종 (claudecli / minimaxcli / qwencli)
agent-tier: paid-only

## 배경

LLM 선정의 입력. 이름은 `usage-<래퍼명>.py` 규약(선정기가 이 이름으로 짝을 찾는다).
참고 구현이 개인 로컬 리포 `~/git/harness-project/.local/bin/tmux-usage-bar.py`의
`claude_usage()`와 `minimax_quota()`에 있다 — 접근 가능하면 **먼저 그 파일을 읽고
데이터 소스(캐시 파일 경로/API)를 그대로 재사용**하고, 접근 불가 환경이면 이 명세로
구현한다. 출력 계약은 `docs/autoqafix-design.md`의 "LLM 선정" 절.

## 요구사항

1. `.claude/skills/autoqafix/usage-claudecli.py`, `.claude/skills/autoqafix/usage-minimaxcli.py`,
   `.claude/skills/autoqafix/usage-qwencli.py` 작성. 모두 PEP-723 헤더(`# /// script`) 포함,
   `uv -q run <파일>`로 실행 가능
2. 출력: JSON 한 줄. 키: `provider`, `five_hour_remaining_pct`,
   `weekly_remaining_pct`, `effective_remaining_pct`(=min(앞의 둘)),
   `available`(bool). 실패 시에도 JSON을 내되 `available:false` +
   `"error":"<요지>"` (stderr 오염 금지, exit 0 유지 — 호출측이 파싱만으로 판단)
3. claude/minimax: tmux-usage-bar.py의 utilization(사용률)을 잔여율로 변환
   (잔여율 = 100 − 사용률). 데이터 취득 함수는 tmux-usage-bar.py에서 복사하되
   출처 주석을 남긴다
4. usage-qwencli.py: 로컬 qwen 서비스 헬스체크. env `QWEN_HEALTH_CMD`(기본:
   `qwen --version`)를 타임아웃 10초로 실행, exit 0이면 UP. UP →
   effective 100/available true, DOWN → 0/false
5. 세 스크립트 모두: env `USAGE_FIXTURE`가 설정되면 그 파일(JSON)을 그대로 읽어
   출력(테스트 주입점)

## 승인 기준

- [ ] `USAGE_FIXTURE=<픽스처>` 지정 시 픽스처 내용이 그대로 한 줄로 나온다
- [ ] `QWEN_HEALTH_CMD=true uv -q run .claude/skills/autoqafix/usage-qwencli.py` →
      `effective_remaining_pct: 100`, `QWEN_HEALTH_CMD=false` → `0`
- [ ] 데이터 소스가 없는 환경(가짜 HOME)에서 usage-claudecli.py가 exit 0 +
      `available:false` JSON을 낸다
- [ ] 세 파일 모두 `uv -q run`으로 기동된다 (PEP-723 유효)

## 검증

`regression-tests/verify-issue-8.sh` 작성: 승인 기준 자동화. 실 API 호출이 있는
경로는 가짜 HOME/픽스처로 차단.
