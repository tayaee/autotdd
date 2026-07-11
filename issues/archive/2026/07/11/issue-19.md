# issue-19: 단일 롤 루프 3종 (autoqa-loop / autofix-loop / autodev-loop)
agent-tier: local-ok

## 배경

합성이 아닌 단일 롤을 주기 실행하는 얇은 루프. autoqafix-loop(issue-18)의
페이즈 로직을 재사용한다.

## 요구사항

1. `.claude/skills/autoqafix/role-loop.py` (PEP-723) 하나로 구현: `--role qa|fix|dev` 인자.
   부팅 대기 없음(합성 루프 전용). 최소 간격(AUTOQAFIX_INTERVAL, 기본 6시간)
   유지하며 해당 1회형을 반복. 테스트 주입점 `AUTOQAFIX_ROLE_CMD`
2. repo 루트 런처 9종: `autoqa-loop.{sh,ps1,bat}`, `autofix-loop.{sh,ps1,bat}`,
   `autodev-loop.{sh,ps1,bat}` — 각각 `role-loop.py --role <r>` 호출,
   issue-14 런처 패턴(uv 검사, `.bat` pause)
3. `--interval <초>` 인자 지원

## 승인 기준

- [ ] `AUTOQAFIX_ROLE_CMD="echo ran"` + `--interval 1`로 `autoqa-loop.sh`
      백그라운드 실행, 3초 후 kill → `ran`이 2회 이상 출력됨
- [ ] interval 도달 전에는 재실행되지 않는다 (`--interval 3600`으로 3초 내 1회만)
- [ ] 런처 9종 존재, `.sh` 3종 `bash -n` 통과

## 검증

`regression-tests/verify-issue-19.sh` 작성: 위 전부 (총 15초 이내).

## 구현 결과

- **구현 완료 일시**: 2026-07-11T01:20:00+09:00
- **변경 파일**: `.claude/skills/autoqafix/role-loop.py`,
  `autoqa-loop.{sh,ps1,bat}`, `autofix-loop.{sh,ps1,bat}`,
  `autodev-loop.{sh,ps1,bat}`, `regression-tests/verify-issue-19.sh`
- **계획과 차이**: issue-18(autoqafix-loop)이 archive에는 있으나 실제로는
  미구현이라 "페이즈 로직 재사용"이 불가능 → role-loop.py에 간격 유지
  로직(`wait_until_interval`)을 자체 구현, 추후 합성 루프가 재사용 가능하게
  함수로 분리. 런처는 issue-14 패턴에 인자 전달(`"$@"`/`@args`/`%*`)을
  추가해 `--interval`이 role-loop.py까지 전달되게 함
- **검증 결과**: verify-issue-19.sh PASS (26/26, 총 6.2초 — 예산 15초 내).
  전체 회귀 스위트 16/16 PASS. 최초 구현 시점(2026-07-11 오전)에는
  verify-issue-15.sh가 main에서 이미 실패 중(issue-16의 step 9(b) 누락)이라
  완료 기준 미충족으로 대기 → issue-16 재작업(커밋 49af40b)으로 해소 후
  완료 처리.
