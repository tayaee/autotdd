# issue-16 리뷰 결과 #1 (by Claude Fable 5)

- **리뷰 일시**: 2026-07-10
- **리뷰 대상**: main(1bbf179) 위의 미커밋 작업본 — `autofix.py` dispatch 실구현,
  `autoqafix_core.py` `run_with_timeout` cwd 추가, `regression-tests/verify-issue-16.sh`
- **판정**: 구현 미완료. `verify-issue-16.sh` 실행 시 TEST 2·3 실패, 이슈 파일
  구현 결과 섹션 `(미정)`. 아래 확정 버그 4건은 전부 실행으로 재현·실증했음.
- **참고 이력**: issue-16은 커밋 5482c91에서 코드 변경 0건으로 아카이브된
  가짜 성공이 있었고, 1bbf179에서 pending으로 복원됨. 현재 작업본이 재구현.

정적 품질 자체는 양호: ruff·pyright 클린, `run_with_timeout`의 `cwd` 파라미터
추가는 최소·적절, 성공 경로(TEST 1)와 FIXED 계수는 동작함.

## A. 확정 버그 (실행으로 재현됨 — 반드시 수정)

### A-1. 실패 기록이 커밋되지 않음 — 승인 기준 직접 위반 (`autofix.py:333-340`)

실패 경로에서 `item.write_text(body)`로 `## agent 실패 기록`을 쓴 뒤 바로
`git mv` → `commit` 한다. `git mv`는 **rename만 스테이징**하고 작업 트리의
내용 수정은 스테이징하지 않으므로, push된 `-agent-failed.md`에는 원본 내용만
있고 실패 기록 섹션이 없다. TEST 2의 두 FAIL(`## agent 실패 기록 section
missing`, `wrapper name missing`)이 이것이다.

부작용: worktree에 미커밋 수정이 남아 다음 실행의 `pull --rebase`까지 위협.

**수정**: `git mv` 후(또는 내용 수정 후) 해당 파일을 `git add` 하고 commit.

### A-2. 래퍼가 archive+push 후 비정상 종료하면 엔진 전체 크래시 (`autofix.py:281-306`)

성공 판정에 `rc == 0`을 전제조건으로 넣었는데, 설계 문서
(docs/autoqafix-design.md "autofix / autodev" 4번)는 "성공 판정 = 항목 파일이
archive로 이동했는가(pull 후 확인)"로 **exit code를 조건으로 두지 않는다**.

재현된 크래시 체인: 래퍼가 archive commit+push까지 성공하고 exit 1 →
실패 경로 진입 → `reset --hard origin/main`(push 반영으로 항목 파일 소멸) →
`write_text`가 untracked 파일 재생성 → `git mv`가 "fatal: not under version
control" → `_git_or_die`의 `RuntimeError`로 run 전체 중단, 후속 항목 미처리.

**수정**: rc와 무관하게(타임아웃 제외) pull 후 archive 존재를 먼저 확인해
성공 처리하고, 실패 경로에서는 reset 후 항목 파일이 실제로 존재하는지 확인.

### A-3. 프로덕션에서 dispatch가 래퍼를 못 찾음 (`autofix.py:269-272`)

dispatch는 `[wrapper, "-p", ...]` — bare 이름 `claudecli`를 PATH에서 찾는다.
실제 래퍼는 `.claude/skills/autoqafix/wrappers/claudecli.sh`이고 PATH에 없다
(CONTEXT.md "LLM 래퍼": PATH 전제는 감싸지는 `claude` 등 실제 CLI뿐).
`judge_tier`(`autofix.py:170-172`)는 `["bash", wrapper_dir/"<name>.sh"]`로
올바르게 호출하는데 dispatch만 다르며, 테스트가 symlink+PATH 주입으로 이를
가려준다. 프로덕션에서는 미포착 `FileNotFoundError`로 크래시한다.

**수정**: judge_tier와 동일하게 `wrapper_dir / f"{selected}.sh"` 경로로 실행
(wrapper_dir을 dispatch에 전달).

### A-4. verify 스크립트의 `extra_env`가 export되지 않음 (`verify-issue-16.sh:76-78`)

`eval "$extra_env"`는 `AUTOQAFIX_IMPL_TIMEOUT=3`을 셸 변수로만 만들어 python
자식에 전달되지 않는다. 그 결과 TEST 3이 기본 10800초 타임아웃 경로로 빠져
fake wrapper의 `sleep 600`을 통째로 기다린 뒤(약 10분 지연) 실패한다.

엔진의 타임아웃 처리 자체는 정상임을 격리 재현으로 확인했다 — env를 제대로
export하면 3초 만에 `-agent-failed`가 origin에 생성됨(단 A-1 때문에 실패
기록 섹션은 여전히 누락).

**수정**: `eval "export $extra_env"` 또는 호출부에서 env 프리픽스로 전달.

## B. 테스트 설계 결함 (승인 기준을 실제로 검증하지 못함)

1. **UNTRACKED_DUMMY 검사가 무의미** (`verify-issue-16.sh:178`, `:428`):
   TEST 1·4 모두 `run_autofix` **이후에** 더미 파일을 만들고 즉시 읽으므로
   항상 통과한다. "사람 main tree의 미커밋 더미 파일이 전 과정에서 불변"
   기준은 실행 **전에** 파일을 만들어야 검증된다.
2. **TEST 4가 실패-후-계속을 검증하지 못함**: 주석은 autofix-1=fail,
   autofix-2=archive지만 실제로는 `FAKE_MODE=archive`+`FAKE_TARGET=autofix-1`
   이라 1번이 성공하고 2번이(FAKE_TARGET 소멸로) 실패한다. 승인 기준
   "실패 항목 뒤에도 다음 항목 처리가 계속된다"는 실패가 **먼저** 나와야
   검증된다.
3. **fake wrapper 인라인 중복 3벌**: issue-18에서 이미 ok/fail/hang/archive
   모드를 지원하도록 확장된 `regression-tests/lib/fake-wrapper.sh`를 쓰지
   않았다. `LIB` 변수는 선언만 되고 미사용. 이슈 명세도 fake-wrapper 사용을
   지시한다.
4. **잔재물/충돌 위험**: 테스트가 `~/.cache/autoqafix/<cid>` 상태 디렉토리를
   만들고 정리하지 않아 축적된다. `/tmp/t1_output` 등 고정 경로는 동시 실행에
   취약. `export HOME="$HOME"`(`verify-issue-16.sh:74`)은 no-op.
   `check_no_zombies`의 전역 `pgrep -f "sleep 600"`은 무관한 프로세스를
   오탐한다(이번 리뷰 중 실제 오탐 발생).

## C. 코드 품질 개선 항목 (사소)

1. `dispatch`의 worktree 재발견 로직(`autofix.py:258-267`)은 불필요 —
   `run()`이 이미 아는 `worktree`를 파라미터로 넘기면 `item.parents` 순회와
   dead 초기값(`item.parent.parent`)이 사라진다. `stem.partition`으로 n을
   뽑아 `f"{stream}-{n}"`을 재조립하는 것도 `item.stem`이면 충분.
2. 모듈 docstring(`autofix.py:9-10`)이 여전히 "dispatch (here a stub — real
   archive dispatch lands in issue-16)" — 낡음.
3. 실패 기록 포맷이 스펙(`- <ISO8601> <래퍼>: <exit code 또는 timeout,
   stderr 마지막 3줄>` 한 불릿)과 달리 stderr가 비들여쓰기 후속 줄로 붙어
   마크다운 리스트가 깨진다. `timeout ({timeout_sec}s)`는 `3.0s`처럼 float
   노출. `body += record` 전에 개행 보장도 없음.
4. 실패 경로의 `_git_or_die`가 push 경합 등으로 예외를 던지면 루프 전체가
   중단된다 — "실패해도 다음 항목 계속" 요건과 상충. `run()` 루프 또는
   dispatch 내부에서 흡수 필요.
5. rc==0인데 pull 실패 또는 미아카이브인 경우 기록 없이 조용히 False —
   항목이 pending으로 남아 다음 실행마다 반복될 수 있다. 정책(재시도 허용 vs
   실패 기록) 명시 필요.
6. `regression-tests/`의 `test1-debug.sh`, `test1-isolated.sh`,
   `test2-isolated.sh`는 디버깅 잔재 — 커밋 전 제거.

## 권장 수정 순서

1. A-1 (실패 기록 `git add` 누락 — 승인 기준 직결)
2. A-3 (래퍼 경로 — 프로덕션 즉사)
3. A-2 (archive+비정상종료 크래시)
4. A-4 + B-1 + B-2 (테스트 수정) → `verify-issue-16.sh` 재실행, 전부 PASS 확인
5. B-3/B-4, C 항목 정리 → 이슈 파일 구현 결과 섹션 기입

## 검증 실행 기록 (2026-07-10)

```
=== TEST 1: FAKE_MODE=archive ===   4 PASS
=== TEST 2: FAKE_MODE=fail ===      2 PASS / 2 FAIL (실패 기록 섹션·래퍼명 누락 = A-1)
=== TEST 3: FAKE_MODE=hang ===      1 PASS / 2 FAIL (A-4로 타임아웃 미전달, 600초 지연)
=== TEST 4: fail + archive ===      3 PASS (단 B-1·B-2로 검증력 없음)
SOME TESTS FAILED
```
