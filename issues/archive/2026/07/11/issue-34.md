# issue-34: verify-issue-21.sh 정리 — 빈 no-op 검사 해소 + 중복 실행 제거
agent-tier: paid-only

## 배경

issue-21 리뷰 종합 판정(`issue-21-feedback-review-by-fable.md` GF-2+GF-3,
원 지적: gemini35 3.2.1/3.2.2, qwen36 4.1, sonnet5 4).

- 144–151행 "실 HOME 오염 검증" 루프가 `:` no-op만 실행하는 빈 껍데기다 —
  검증하는 척하지만 아무것도 assert하지 않는다("빈 검사" 함정). 144행의
  `${HOME:-$HOME}` 기본값 지정도 문법상 무의미하다.
- 92/106행에서 이미 install.sh를 1·2차 실행해놓고, exit code만 얻으려고
  112–113행에서 3·4차 재실행한다. 1·2차 실행 시점에 rc를 캡처하면 제거
  가능 (issue-29의 "usage 중복 실행 제거"와 같은 유형).

**선행**: 없음. 단 issue-33이 같은 파일의 시나리오를 참조하므로 순차 처리
권장 (autotdd 관례상 한 번에 한 이슈라 자연 충족).

## 요구사항

1. 빈 no-op 루프(144–151행) 해소 — 둘 중 하나를 선택하고 이유를 구현
   결과에 기록:
   - (권장) **실검증화**: 설치 전 실 HOME의 `~/.claude/skills` 내
     대상 4개 항목의 상태(존재 여부·inode 또는 mtime)를 스냅샷해 두고,
     fake HOME 설치 후 스냅샷과 동일함을 assert
   - 또는 **제거**: 격리가 fake HOME으로 구조적으로 보장됨을 주석 한 줄로
     남기고 루프·`real_home_skills` 변수 삭제
   어느 쪽이든 `${HOME:-$HOME}` 표현은 사라져야 한다.
2. 중복 실행 제거: 1차(92행)·2차(106행) 실행의 exit code를 그 시점에
   `rc1`/`rc2`로 캡처하고 112–113행의 3·4차 실행을 삭제. "1차/2차 exit
   code 동일" 검사 자체는 유지.
3. 수정 후에도 verify-issue-21.sh의 기존 PASS 항목 수와 검사 의미가
   보존되어야 한다 (검사 축소 금지 — no-op 루프 제거를 택한 경우만 예외이며
   그 루프는 원래 검증력이 0이었음을 근거로 명시).

## 승인 기준

- [ ] `grep -c 'bash "$INSTALL_SH"' regression-tests/verify-issue-21.sh` = 2
      (1·2차 실행만 남음)
- [ ] `grep -n ':-\$HOME' regression-tests/verify-issue-21.sh` 매치 0건
- [ ] no-op `:`만 있는 검증 루프가 없음 (실검증 assert 또는 삭제+주석)
- [ ] `bash regression-tests/verify-issue-21.sh` PASS
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-34.sh` 작성: grep 기반 — install.sh 호출
횟수 2회, `${HOME:-$HOME}` 부재, no-op 루프 부재를 검사한 뒤
verify-issue-21.sh를 1회 실행해 여전히 전체 PASS인지 확인
(issue-31의 grep 기반 verify와 동일 패턴).

## 구현 결과

* **구현 완료 일시**: 2026-07-11T19:35:00-04:00
* **변경 파일**:
  * `regression-tests/verify-issue-21.sh`:
    * 빈 no-op 루프(구 144–151행) → **실검증화**(권장안 채택): fake-HOME
      설치 실험 전 실 `$HOME/.claude/skills`의 대상 4개 항목 상태(존재 시
      `inode:mtime`, 부재 시 `ABSENT`)를 `real_snapshot` 연관 배열에
      스냅샷하고, 실험 후 동일 로직으로 재측정해 스냅샷과 일치하는지
      `pass`/`fail`로 assert (4건 신규 검증). `${HOME:-$HOME}` 무의미
      표현 제거, 실제 호스트 HOME은 스크립트 진입 시 잡아둔
      `REAL_HOME_SKILLS="$HOME/.claude/skills"`로 대체
    * 중복 실행 제거: 1차(舊 92행)·2차(舊 106행) 실행에서 `if ... ; then
      ... else rc=$?; fi` 형태로 그 자리에서 `rc1`/`rc2`를 캡처하도록
      바꾸고, exit code만 얻으려던 3·4차 재실행(舊 112–113행)을 삭제.
      "1차/2차 exit code 동일" 검사는 그대로 유지 (캡처된 rc1/rc2로 비교)
  * `regression-tests/verify-issue-34.sh` (신규 — install.sh 호출 횟수 2,
    `${HOME:-$HOME}` 부재, no-op `:` 단독 라인 부재, verify-issue-21.sh
    자체 PASS = 4개 검증)
* **계획 대비 변경 사항**: 없음 (요구사항 1~3 그대로 수행, 1번은 권장안인
  실검증화를 선택 — 제거안보다 실제 검증력을 갖도록)
* **검증 결과**:
  * `verify-issue-34.sh` PASS — 4개 검증 모두 통과
  * `verify-issue-21.sh` PASS — 기존 17개 PASS 항목이 실검증 4개로
    치환·확장돼 총 17개(no-op 3개 제거 + 실검증 4개 = 순증 1개) 검증,
    검사 의미 축소 없음
  * `python3 -m py_compile` 대상 없음 (본 이슈는 회귀 테스트 셸 스크립트만 변경)
  * repo 루트에 `pyproject.toml` 없어 ruff/pyright/pytest 단계는 tdd2
    규칙대로 생략
  * 전체 회귀 테스트: 기존 28개(issue-32/33 포함) + 신규
    `verify-issue-34.sh` = 29개 전부 PASS
