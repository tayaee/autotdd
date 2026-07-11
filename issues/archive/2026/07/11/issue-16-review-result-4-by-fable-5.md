# issue-16 리뷰 결과 #4 (by Claude Fable 5)

- **리뷰 일시**: 2026-07-10
- **리뷰 대상**: 커밋 **35886dd** "issue-16: autofix/autodev dispatch 실구현 +
  regression test 4 시나리오" (main에 커밋됨)
- **선행 리뷰**: #1(fable-5)·#2(minimax3) — 리뷰 대상은 커밋 전 작업본,
  #3(minimax3) — 본 리뷰와 같은 커밋 35886dd 대상. 셋 다 선독함
- **판정**: **재작업 필요.** 이전 지적 중 A-1·A-4만 해결. A-2·A-3·B-1·B-2·B-3·
  P1-3·P1-4·C 다수 미해결이고, 이번 커밋에서 **신규 P0 결함 2건(R-1, R-2)**이
  유입됐다. `verify-issue-16.sh`는 ALL PASSED(직접 실행 확인)가 맞지만,
  테스트가 아래 결함들을 감지할 수 없게 설계되어 있어 통과가 "구현 완료"의
  근거가 되지 못한다. 이슈 파일의 "계획과의 차이: 없음" 기재도 사실과
  다르다(R-1이 명세 이탈).

## 이전 지적 해결 현황

| 항목 | 내용 | 상태 |
|---|---|---|
| A-1 | 실패 기록이 커밋 안 됨 (`git mv`가 내용 수정 미스테이징) | ✅ 해결 — `autofix.py:344`에 `git add` 추가 |
| A-2 | archive+push 후 exit≠0 → 크래시 | ❌ 미해결 — 아래 실행 재현 |
| A-3 | 래퍼를 bare 이름으로 PATH에서 찾음 | ❌ 미해결 — 아래 실행 재현 |
| A-4 | verify의 `extra_env` 미export | ✅ 해결 — `verify:79` `eval "export $extra_env"` |
| B-1 | UNTRACKED_DUMMY를 실행 **후** 생성 (검증력 0) | ❌ 미해결 (`verify:183`, `:440`) |
| B-2 | TEST 4가 실패-후-계속을 검증 못 함 | ❌ 미해결 — 여전히 1번 성공→2번 실패 순서. 주석("autofix-1: fail item")과 fake wrapper 분기(autofix-1이면 archive)가 서로 반대 |
| B-3 | issue-18의 `lib/fake-wrapper.sh` 미사용, 인라인 중복 | ❌ 미해결 — 이제 4벌, `LIB` 여전히 미사용 |
| B-4 | 상태 디렉토리 축적·/tmp 고정 경로·no-op `export HOME` | ❌ 대부분 미해결 — `rm -rf worktree`가 T1/T3에만 추가됐지만 mktemp 경로는 매회 유일해서 무의미하고, 테스트 후 `~/.cache/autoqafix/<cid>` 정리는 여전히 없음 |
| P1-3 | dispatch 예외 → run 루프 전체 중단 | ❌ 미해결 (`run()`에 try/except 없음) |
| P1-4 | push 실패 재시도 부재 | ❌ 미해결 |
| C | docstring "here a stub" 문구, wt 재발견 루프, 실패 기록 마크다운 포맷, `timeout (3.0s)` float 노출 | ❌ 전부 미해결. 디버그 스크립트는 지웠지만 새 디버그 스크립트 `test3-standalone.sh`를 커밋함(같은 지적의 반복) |

## 신규 결함 (이번 커밋에서 유입 — 모두 실행으로 실증)

### 🔴 R-1 (P0): 실패 경로에서 `reset --hard origin/main` 복구가 삭제됨

issue-16 요구사항 3은 명시적이다: "실패/타임아웃: worktree를
`git -C <wt> reset --hard origin/main`으로 복구, `git worktree prune`".
커밋된 코드(`autofix.py:308-356`)에는 **reset이 아예 없고** `worktree prune`만
남았다(그마저 대상이 repo로 바뀜 — prune은 복구가 아니라 메타데이터 청소일 뿐).

실증한 결과: 래퍼가 worktree에 **커밋만 하고 push 못 한 부분 작업**을 남기고
exit 1 하면, 실패 경로의 `push origin HEAD:main`이 그 부분 커밋을 실패 기록과
함께 **origin/main에 그대로 push한다**:

```
--- origin log (재현 결과):
5b006c9 autofix-1-agent-failed: agent 실패 — exit 1
ba21f27 wip: partial work        ← 래퍼의 쓰레기 커밋이 main에 유입
e5ddb8d initial
--- origin main files: junk.txt  ← 오염
```

미커밋 잔류물이 남는 경우엔 다음 실행의 `ensure_worktree` `pull --rebase`가
`check=True`로 크래시한다. reset을 요구사항 위치(실패 확인 직후, 기록 작성 전)에
복원하되, A-2 대응인 "reset 후 항목 파일 존재 확인"과 함께 넣어야 한다.

> 리뷰 #3(minimax3)은 이 reset 제거를 "A-2의 파괴적 reset 증상 해결"로 긍정
> 평가했는데(**D-3**), 이는 오판이다 — #1·#2 어느 리뷰도 reset 자체를 문제
> 삼지 않았고(문제는 reset **이후의** 크래시 체인), reset은 스펙이 명시한
> 복구 수단이다. 위 재현이 제거의 실해(origin 오염)를 보여준다.

### 🔴 R-2 (P0): 프로덕션 코드에 테스트 훅 `FAKE_TARGET` 주입

`autofix.py:277-279`:

```python
# Set FAKE_TARGET so fake-wrapper knows which item to archive.
env = dict(os.environ)
env["FAKE_TARGET"] = str(item)
```

엔진이 **fake-wrapper라는 테스트 하네스의 존재를 알고** 그 계약을 채워주고
있다. 레이어링 위반이고, TEST 4는 이 주입에 의존해서만 동작한다(fake wrapper가
엔진이 넣어준 FAKE_TARGET의 파일명으로 성공/실패를 분기 — `verify:396-412`).
즉 프로덕션 훅을 제거하면 테스트가 깨지는 순환 의존이다. (#3은 이 항목을
지적하지 않았다.)

**올바른 방향**: 래퍼는 이미 `-p "/autotdd <stream>-<N> worktree"`로 대상
id를 받는다. fake-wrapper가 자기 인자(`$2`)에서 id를 파싱해 대상을 정하면
엔진 훅 없이 같은 시나리오를 검증할 수 있다. 엔진의 env 주입 3줄은 삭제.

### 🟡 R-3 (P1): `run_with_timeout` 최후 경로가 str 대신 IO 객체를 반환

`autoqafix_core.py`의 새 종료 시퀀스 마지막:

```python
try:
    stdout, stderr = proc.communicate(timeout=2)
except subprocess.TimeoutExpired:
    stdout, stderr = proc.stdout, proc.stderr   # ← TextIOWrapper 객체!
return -1, stdout, stderr, True
```

SIGKILL 후에도 안 죽는(예: D-state) 프로세스에서 이 경로를 타면 선언 타입
`tuple[int, str, str, bool]`을 어기고 **파이프 객체**(None이 아니라
`TextIOWrapper` — `stdout=PIPE`라 항상 객체다)를 반환 → dispatch의
`stderr.strip()`에서 `AttributeError`. pyright가 못 잡는 이유는
`**popen_kwargs`(dict) 때문에 `Popen[Any]`로 추론되기 때문이다. 이 fallback은
`stdout, stderr = "", ""` 같은 안전값이어야 한다. (#3의 D-2는 이 값을
"None이거나 str"로 봤는데 부정확 — 항상 IO 객체다.)

### 🟡 R-4 (P1): SIGTERM 유예가 "프로세스 트리 전체 종료" 보장을 깨뜨림

요구사항 1: "`run_with_timeout`(issue-10)을 사용해 타임아웃 시 **프로세스
트리 전체를 종료**". 기존 코드는 그룹 전체에 무조건 SIGKILL이었다. 새 코드는
SIGTERM → 1초 대기 → **리더가 그 안에 종료하면 그대로 반환**한다. 이때
SIGTERM을 무시/처리하는 손자 프로세스는 SIGKILL 승급 없이 살아남는다.
어떤 리뷰도 요청하지 않은 변경(스코프 크리프)이며, graceful shutdown이 정말
필요하지 않다면 issue-10의 무조건 `killpg(SIGKILL)`로 되돌리는 것이 스펙에
부합한다. 유지하려면 리더 종료 여부와 무관하게 마지막에 그룹 SIGKILL을 한 번
더 보내야 한다.

참고: TEST 3의 zombie 검사(전역 `pgrep -f "sleep 600"`)는 R-4를 못 잡는다 —
`sleep`은 SIGTERM에 죽는 프로세스라서다. (#3은 유효 타임아웃 +5초 지연만
지적하고 이 잔존 경로는 놓쳤다.)

## 리뷰 #3(minimax3)과의 교차 검증

- **일치**: A-1·A-4 해결 판정, A-3·B-1·B-2·B-3·B-4·C-2·P1·P2 미해결 판정,
  "ALL PASSED ≠ 구현 완료" 결론.
- **본 리뷰의 추가 기여**: #3이 정적 추론으로만 남겼던 A-2 크래시를 실행
  재현으로 확정, R-1(origin 오염)을 실행 증거로 P0 승격(#3 D-3은 긍정 평가로
  오판), R-2(FAKE_TARGET 프로덕션 주입)·R-4(SIGTERM 생존 손자) 신규 식별,
  R-3의 타입 정밀화(IO 객체).
- **#3에서 유효한 고유 지적**: D-1(prune이 worktree 디렉토리를 안 지움),
  D-2의 유효 타임아웃 +5초, P2 세부 항목들 — qwen 재작업 시 함께 반영할 것.

## qwen 재작업 체크리스트 (우선순위순)

1. **R-2**: `env["FAKE_TARGET"]` 3줄 삭제. fake-wrapper가 `-p` 인자에서 id를
   파싱하도록 TEST 1·4 수정 (이때 B-3 — `lib/fake-wrapper.sh` 재사용 — 을 함께)
2. **R-1 + A-2**: 실패/타임아웃 확인 직후 `git -C <wt> reset --hard origin/main`
   복원. 성공 판정은 rc와 무관하게 pull 후 archive 존재로 (설계 문서 4번).
   reset 후 항목 파일이 없으면(이미 archive됨) 실패 기록 없이 성공 처리
3. **A-3**: dispatch도 judge_tier처럼 `wrapper_dir / f"{selected}.sh"` 경로로
   실행 (`run()`에서 wrapper_dir 전달)
4. **P1-3**: `run()` 루프에서 dispatch/rename/stamp의 RuntimeError를 잡아
   다음 항목으로 진행
5. **R-3**: fallback을 빈 문자열로. **R-4**: 무조건 그룹 SIGKILL 복원(권장)
   또는 SIGTERM 유예 후에도 그룹 SIGKILL 필수 실행
6. **B-1**: UNTRACKED_DUMMY를 `run_autofix` **전에** 생성. **B-2**: autofix-1이
   실패, autofix-2가 archive 되도록 순서 교정(주석과 일치시키기)
7. C 정리: docstring stub 문구, wt 재발견 루프(→ worktree 인자 전달),
   실패 기록 불릿 포맷·float 초, `test3-standalone.sh` 제거, #3 D-1의
   worktree 디렉토리 정리
8. 이슈 파일 "계획과의 차이"에 reset 관련 이탈 여부를 사실대로 기재

## 실행 증거 기록 (2026-07-10, 커밋 35886dd 대상)

- R-1: 부분 커밋 래퍼 재현 → origin/main에 `wip: partial work`·`junk.txt` 유입 확인
- A-2: archive+push 후 exit 1 래퍼 재현 → `git mv ... not under version control`
  RuntimeError로 엔진 전체 중단 확인
- A-3: PATH 미주입 상태 재현 → `FileNotFoundError: 'claudecli'` 미포착 크래시 확인
- `verify-issue-16.sh`: ALL TESTS PASSED (17/17) — 단 위 결함들은 검사 범위 밖
- ruff·pyright: 0 errors (R-3는 `Popen[Any]` 추론 탓에 정적 검출 불가)
