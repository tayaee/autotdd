# issue-28: doctor 스킬 검사 중복 FAIL dedupe
agent-tier: local-ok

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` G1,
원 지적: gemini ①, deepseek #1). doctor의 `check_preflight("fix")`가
내부에서 `~/.claude/skills/{autotdd,tdd2,acpd}` 부재를 FAIL로 계수하고,
뒤이은 `check_skills()`가 같은 3종(+`tdd`)을 다시 검사한다. 스킬 하나가
없으면 동일 결함이 **FAIL 2건으로 이중 계수**되어 exit code가 실제 결함
수보다 부풀려진다. (참고: doctor가 `tdd`까지 4종을 보는 것 자체는
issue-20 스펙 ⑦의 명시 요구 — 축소 금지.)

## 요구사항

1. 동일한 스킬 부재가 FAIL 2건으로 계수되지 않도록 dedupe —
   권장안(리뷰 합의 A안): `check_skills()`는 preflight가 검사하지 않는
   `tdd`만 FAIL 계수 대상으로 하고, preflight와 겹치는 3종은 preflight
   결과에 위임(출력 중복도 제거). 다른 방식을 택해도 되나 "exit code =
   고유 결함 수" 불변식을 지켜야 한다
2. 4종 모두 정상일 때의 출력(`OK 스킬 <name>` 4줄)은 유지 — 진단 리포트
   가독성 보존

## 승인 기준

- [ ] 스킬 1종 부재 픽스처(HOME 오버라이드)에서 해당 부재로 인한 FAIL이
      정확히 1건 (preflight 쪽 또는 check_skills 쪽 한 곳)
- [ ] exit code = 화면의 FAIL 라인 수 = 고유 결함 수
- [ ] 4종 모두 존재 시 `OK 스킬` 4줄 출력 유지
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-28.sh` 작성: 가짜 HOME에 스킬 3종만 설치한
픽스처로 ① 부재 1종 → FAIL 1건·exit 일치, ② 4종 설치 → OK 4줄 확인.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T13:05:00-04:00
- **변경 파일**:
  `.claude/skills/autoqafix/autoqafix-doctor.py` (check_skills dedupe),
  `regression-tests/verify-issue-28.sh` (시나리오 3종)
- **계획과 차이**:
  - 리뷰 합의 A안 채택: `check_skills()`는 preflight가 검사하지 않는
    `tdd`만 FAIL 계수 대상으로 하고, preflight와 겹치는
    `{autotdd,tdd2,acpd}` 3종은 OK 줄만 출력하고 부재 시 silent
    (preflight에 위임). 4종 모두 정상일 때의 `OK 스킬 <name>` 4줄
    출력은 유지.
  - 부수 정리: `autoqafix-doctor.py`의 미사용 `import socket` 제거
    (ruff FAIL — issue-20 잔여. 이번 변경의 검증 게이트 통과를 위해 정리).
- **검증 결과**: verify-issue-28.sh ALL PASS (9 PASS, 0 FAIL).
  전체 회귀 테스트 22/22 PASS. ruff/pyright/compileall PASS.
