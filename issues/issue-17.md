# issue-17: autoqafix-doctor — 사전 점검 도구

## 배경

"이 repo에서 스위트가 동작할 것인가"를 사람이 실행 전에 최대한 확인하는 진단.
preflight(issue-9)의 상위 집합이다.

## 요구사항

1. `.claude/skills/autoqafix/autoqafix-doctor.py` (PEP-723) + repo 루트 런처
   `autoqafix-doctor.{sh,ps1,bat}`
2. 검사 항목(각각 `OK <항목>` 또는 `FAIL <항목>` + `[원인]`/`[조치]` 출력):
   ① preflight("qa")·preflight("fix") 전 항목, ② `AUTOQAFIX_WRAPPERS`의 래퍼들이
   스킬 폴더 `wrappers/` 또는 PATH에 존재, ③ 후보 래퍼들의 usage 스크립트
   (`usage-<래퍼명>.py`)가 `uv -q run`으로 기동되고 유효 JSON을
   내는가, ④ select-llm이 후보 래퍼명 또는 `none`을 내는가,
   ⑤ `deploy-to-dev.*`가 대상 repo에 존재하는가(없으면 FAIL이 아닌
   `WARN — acpd가 deploy 단계에서 생성 시도함` 출력), ⑥ 뮤텍스 잠금이 현재
   잡혀 있지 않은가, ⑦ `~/.claude/skills/{autotdd,tdd2,acpd,tdd}` 존재
3. `--ping` 플래그: 후보 래퍼의 `ping-<래퍼명>`도 실행(크레딧 소모 경고를
   먼저 출력하고 진행). 기본은 실행하지 않음
4. exit code = FAIL 항목 수 (WARN은 세지 않음)

## 승인 기준

- [ ] 완전한 픽스처 repo에서 FAIL 0, exit 0
- [ ] `logs/` 삭제 → FAIL ≥ 1, exit ≥ 1, 해당 항목에 `[조치]`가 있다
- [ ] `deploy-to-dev.sh` 없는 픽스처에서 WARN은 나오되 exit에 반영 안 됨
- [ ] `--ping` + PING_WRAPPER=fake로 ping 결과가 출력에 포함된다

## 검증

`regression-tests/verify-issue-17.sh` 작성: 위 전부.
