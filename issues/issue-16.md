# issue-16: 단일 롤 루프 3종 (autoqa-loop / autofix-loop / autodev-loop)

## 배경

합성이 아닌 단일 롤을 주기 실행하는 얇은 루프. autoqafix-loop(issue-15)의
페이즈 로직을 재사용한다.

## 요구사항

1. `.claude/skills/autoqafix/role-loop.py` (PEP-723) 하나로 구현: `--role qa|fix|dev` 인자.
   부팅 대기 없음(합성 루프 전용). 최소 간격(AUTOQAFIX_INTERVAL, 기본 6시간)
   유지하며 해당 1회형을 반복. 테스트 주입점 `AUTOQAFIX_ROLE_CMD`
2. repo 루트 런처 9종: `autoqa-loop.{sh,ps1,bat}`, `autofix-loop.{sh,ps1,bat}`,
   `autodev-loop.{sh,ps1,bat}` — 각각 `role-loop.py --role <r>` 호출,
   issue-13 런처 패턴(uv 검사, `.bat` pause)
3. `--interval <초>` 인자 지원

## 승인 기준

- [ ] `AUTOQAFIX_ROLE_CMD="echo ran"` + `--interval 1`로 `autoqa-loop.sh`
      백그라운드 실행, 3초 후 kill → `ran`이 2회 이상 출력됨
- [ ] interval 도달 전에는 재실행되지 않는다 (`--interval 3600`으로 3초 내 1회만)
- [ ] 런처 9종 존재, `.sh` 3종 `bash -n` 통과

## 검증

`regression-tests/verify-issue-16.sh` 작성: 위 전부 (총 15초 이내).
