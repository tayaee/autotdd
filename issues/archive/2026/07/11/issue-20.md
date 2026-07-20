# issue-20: autoqafix-doctor — 사전 점검 도구
agent-tier: paid-only

## 배경

"이 repo에서 스위트가 동작할 것인가"를 사람이 실행 전에 최대한 확인하는 진단.
preflight(issue-10)의 상위 집합이다.

## 요구사항

1. `.claude/skills/autoqafix/autoqafix-doctor.py` (PEP-723) + repo 루트 런처
   `autoqafix-doctor.{sh,ps1,bat}`
2. 검사 항목(각각 `OK <항목>` 또는 `FAIL <항목>` + `[원인]`/`[조치]` 출력):
   ① preflight("qa")·preflight("fix") 전 항목, ② `AUTOQAFIX_WRAPPERS`의 래퍼들이
   스킬 폴더 `wrappers/` 또는 PATH에 존재, ③ 후보 래퍼들의 usage 스크립트
   (`usage-<래퍼명>.py`)가 `uv -q run`으로 기동되고 유효 JSON을
   내는가, ④ select-llm이 후보 래퍼명 또는 `none`을 내는가,
   ⑤ `deploy.{sh,ps1,bat}` 또는 `deploy-to-env.{sh,ps1,bat}`가 대상 repo에
   존재하는가 — 이 파일은 대상 repo가 준비하는 것이며 스킬은 절대 생성하지
   않는다(없으면 FAIL이 아닌 `WARN — deploy 스크립트 없음, 파일이 없으므로
   배포는 생략됩니다` 출력), ⑥ 뮤텍스 잠금이 현재
   잡혀 있지 않은가, ⑦ `~/.claude/skills/{autotdd,tdd2,aacpd,tdd}` 존재
3. `--ping` 플래그: 후보 래퍼의 `ping-<래퍼명>`도 실행(크레딧 소모 경고를
   먼저 출력하고 진행). 기본은 실행하지 않음
4. exit code = FAIL 항목 수 (WARN은 세지 않음)

## 승인 기준

- [ ] 완전한 픽스처 repo에서 FAIL 0, exit 0
- [ ] `logs/` 삭제 → FAIL ≥ 1, exit ≥ 1, 해당 항목에 `[조치]`가 있다
- [ ] deploy 스크립트(`deploy.sh`/`deploy-to-env.sh`) 없는 픽스처에서 WARN은
      나오되 exit에 반영 안 됨
- [ ] `--ping` + PING_WRAPPER=fake로 ping 결과가 출력에 포함된다

## 검증

`regression-tests/verify-issue-20.sh` 작성: 위 전부.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T01:14:00+09:00
- **변경 파일**: `.claude/skills/autoqafix/autoqafix-doctor.py`,
  `autoqafix-doctor.{sh,ps1,bat}`, `regression-tests/verify-issue-20.sh`
- **계획과 차이**: 없음. 세부 판단 2건 — ① preflight는 실패 메시지만
  반환하므로 항목 단위 OK는 role 단위(`OK preflight(qa)`)로, FAIL은
  preflight 실패 메시지 1건당 `FAIL preflight(<role>)` 1줄로 계수.
  ② `--ping`의 ping 스크립트는 `AUTOQAFIX_WRAPPER_DIR`에서 먼저 찾고
  없으면 스킬의 `wrappers/`로 폴백 (테스트 주입과 실환경 모두 지원)
- **검증 결과**: verify-issue-20.sh PASS (15/15, 2.5초).
  전체 회귀 스위트 17/17 PASS. 구현 중 잡은 버그: `any(glob제너레이터)`가
  내용이 아닌 제너레이터 객체를 평가해 deploy 부재를 OK로 오판 → 수정.
