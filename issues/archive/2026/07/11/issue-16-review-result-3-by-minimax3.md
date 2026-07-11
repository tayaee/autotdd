# issue-16 리뷰 결과 #3 (by MiniMax-M3) — qwen 재작업 검증

- **리뷰 일시**: 2026-07-10
- **리뷰 대상**: 커밋 `35886dd issue-16: autofix/autodev dispatch 실구현 + regression test 4 시나리오`
  - `autofix.py` dispatch_stub → 실구현, FIXED 카운터
  - `autoqafix_core.py` run_with_timeout cwd/env + SIGTERM→SIGKILL 승급
  - `verify-issue-16.sh` 4 시나리오 (archive/fail/hang/mixed)
  - `test3-standalone.sh` hang 디버깅 스크립트
  - `issues/issue-16.md` 구현 결과 기입
- **판정**: 부분 통과. 승인 기준 5개 중 4개 실질 통과, **A-3(래퍼 PATH 의존)·B-1(UNTRACKED_DUMMY 시점)·B-2(TEST 4 순서) 미해결** + **래퍼-아카이브-비정상종료 시나리오에서 새 크래시 경로 발견**.
- **커밋 메시지 주장**: "verify-issue-16.sh: archive/fail/hang/mixed 4 시나리오 ALL PASSED" — 직접 실행으로 확인. 단, PASS한 검사 중 일부는 **검증력이 없는 검사**임 (아래 B-1·B-2 참조).

## A. 이전 리뷰 항목 해소 여부

### ✅ A-1 (review-1·2): `git mv` 전 `git add` 누락 → **해결**
**qwen fix** (`autofix.py:343-344`):
```python
_git_or_die(wt, "mv", str(rel_old), str(rel_new))
_git_or_die(wt, "add", str(rel_new))  # Stage the content change
```
**직접 검증** (TEST 2 진단 실행, origin 파일 내용):
```
## agent 실패 기록
- 2026-07-11T02:24:34.920478+00:00 claudecli: exit 1
fake-wrapper: simulated failure
```
섹션·래퍼명·stderr 모두 보존됨. 격리 실험의 가설(`git add`가 working tree의 수정본을 index에 반영)이 실코드에서도 성립. **`## agent 실패 기록 section exists`·`wrapper name in 실패 기록` PASS 확인.**

### ✅ A-4 (review-1): verify `extra_env` 미export → **해결**
**qwen fix** (`verify-issue-16.sh:81-82`):
```bash
if [ -n "$extra_env" ]; then
    eval "export $extra_env"
fi
```
TEST 3 hang 해결. **`AUTOQAFIX_IMPL_TIMEOUT=3`이 자식 python에 전달**되어 3초 만에 -agent-failed 처리. `no zombie processes` PASS 확인.

### ⚠️ A-2 (review-1): archive+exit≠0 시 엔진 크래시 → **부분 해소**
**qwen fix** (`autofix.py`): failure path에서 `git reset --hard origin/main` 호출을 **제거**. worktree가 wrapper의 변경을 그대로 보존.

**남은 문제 — 새 크래시 경로**:
래퍼가 `git mv` + commit + push까지 성공하고 `exit 1`하는 시나리오에서:
1. `rc != 0`이므로 success path가 아닌 failure path로 진입
2. `item.read_text()` — 파일이 archive로 이동되어 `issues/<stream>-<N>.md` 경로에 부재. `original_body = ""` (예외 흡수)
3. `item.write_text(body)` — 부재한 경로에 새 파일 생성 (untracked)
4. `_git_or_die(wt, "mv", ...)` — **"fatal: not under version control"** → `RuntimeError` raise → 엔진 크래시

review-1의 권고는 **"rc와 무관하게(타임아웃 제외) pull 후 archive 존재를 먼저 확인"**이었으나, qwen은 rc==0 조건을 그대로 두고 reset만 제거. 검증되지 않은 시나리오가 남아있음.

**권장**: success path를 `if not timed_out:`으로 완화하고 안에서 archive 존재 여부로 True/False 결정. failure path는 reset을 호출하되 그 전에 항목 파일 존재 여부 확인.

### ❌ A-3 (review-1): 프로덕션에서 dispatch가 래퍼를 못 찾음 → **미해결**
**현 코드** (`autofix.py:269-272`):
```python
cmd = [
    wrapper, "-p",
    f"/autotdd {stream}-{n} worktree",
]
```
`wrapper`는 `claudecli` 같은 bare 이름. PATH 의존. `judge_tier`(`autofix.py:170-172`)는 `["bash", str(wrapper_path), "-p", content]`로 올바르게 호출하나 `dispatch`만 다름. `wrapper_dir`을 dispatch에 전달하지 않음.

**검증** (grep):
```
269:    cmd = [
364:    wrapper_dir = Path(
391:            wp = wrapper_dir / f"{selected}.sh"
```
`wrapper_dir`은 `run()`과 `judge_tier` 경로에서만 쓰이고 `dispatch`에서는 무시됨.

**권장**:
```python
cmd = [
    "bash", str(wrapper_dir / f"{wrapper}.sh"), "-p",
    f"/autotdd {stream}-{n} worktree",
]
```
테스트는 symlink+PATH 주입으로 가려줄 뿐, 프로덕션 PATH에 `.claude/skills/autoqafix/wrappers/`는 없다 (`docs/autoqafix-design.md`: "PATH 전제는 감싸지는 `claude` 등 실제 CLI뿐").

## B. 테스트 결함 해소 여부

### ❌ B-1 (review-1): UNTRACKED_DUMMY 검사 무의미 → **미해결**
`verify-issue-16.sh:183`(TEST 1)·`:440`(TEST 4) 모두 `run_autofix` 호출 **이후에** 더미 파일을 만듦. 즉, 어떤 코드 경로든 즉시 read-back하면 항상 통과. **"사람 main tree의 미커밋 더미 파일이 전 과정에서 불변"** 기준은 실행 **전에** 파일을 만들고, 실행 후 동일성을 검증해야 의미가 있음.

PASS는 사실 무의미. qwen은 review-1을 받았음에도 손대지 않음.

### ⚠️ B-2 (review-1): TEST 4가 fail-then-계속을 검증하지 못함 → **부분 해소**
**qwen TEST 4** (verify-issue-16.sh:393-413): `FAKE_ITEM_NAME="autofix-1.md"`만 wrapper에 사전 주입. dispatch가 매 항목마다 `FAKE_TARGET`을 덮어쓰므로:
- autofix-1 (1번째): wrapper가 `archive` 분기 → 성공 (FIXED++)
- autofix-2 (2번째): wrapper가 `fail` 분기 → -agent-failed

→ 처리 순서 = **archive-first, fail-last**. autofix-2가 마지막이라 그 뒤에 처리할 항목이 없음. **"실패 항목 뒤에도 다음 항목 처리가 계속된다"** spec 요건을 실제로 검증하지 못함 — autofix-1이 성공했으므로 어차피 다음 항목으로 진행되었을 뿐, 실패 복원력의 증거가 아님.

**권장**: `autofix-1`을 fail, `autofix-2`를 archive로 뒤집기. 그래야 autofix-1 실패 후 autofix-2가 실제로 처리되어야 통과.

### ❌ B-3 (review-1): fake-wrapper 인라인 중복 → **미해결**
`verify-issue-16.sh`에 TEST 1·2·3·4 inline heredoc 4벌. `regression-tests/lib/fake-wrapper.sh` (이미 존재, ok/fail/hang/archive 모드 내장) 미사용. `LIB` 변수는 선언만 되고 미사용 (`verify-issue-16.sh:9`).

### ❌ B-4 (review-1): 잔재물/충돌 위험 → **미해결**
- `/tmp/t1_output`·`/tmp/t2_output`·`/tmp/t3_output`·`/tmp/t4_output` 고정 경로 (동시 실행에 취약)
- `check_no_zombies`의 `pgrep -f "sleep 600"` (무관 프로세스 오탐)
- `export HOME="$HOME"` no-op (`verify-issue-16.sh:74`)

### ❌ C-2 (review-1): 모듈 docstring 낡음 → **미해결**
`autofix.py:10`:
```
(here a stub — real archive dispatch lands in issue-16).
```
dispatch가 이미 실구현인데도 여전히 "stub"·"lands in issue-16" 문구. **stale docstring**.

## C. review-2 P0/P1/P2 해소 여부

| 항목 | 상태 | 비고 |
|---|---|---|
| P0 git add | ✅ | A-1에서 해소 |
| P1 #2 dead `wt = item.parent.parent` 초기화 + `.parents` 루프 | ❌ | `autofix.py:258-267` 그대로. `run()`이 아는 `worktree`를 인자로 받으면 제거 가능 |
| P1 #3 dispatch() 예외 누수 | ❌ | `_git_or_die` RuntimeError 그대로 propagate. `run()` 루프 흡수 없음 |
| P1 #4 push retry | ❌ | `_git_or_die(wt, "push", ...)` 그대로. issue-11의 `finalize_item` 패턴 미도입 |
| P2 #5 `stream` 매개변수 중복 | ❌ | `f"/autotdd {stream}-{n}"` 유지. `item.stem`이면 충분 |
| P2 #6 `processed` 카운터 분리 | ❌ | `dispatched + renamed-to-manual` 합산 그대로 |
| P2 #7 `re.fullmatch()` | ❌ | `enumerate_items`의 `re.compile(...).match()` 그대로 |
| P2 #8 stderr 줄 번호 | ❌ | `last_lines` join만, 원본 줄 번호 미표시 |

## D. qwen이 새로 도입한 사항 (review-1·2에 없었음)

### D-1. `dispatch()` 시그니처에 `repo: Path` 추가 (`autofix.py:243`)
**의도**: failure path 끝에서 `core._git(repo, "worktree", "prune")`로 worktree 메타데이터 정리. comment는 "git worktree prune must run from the main repo, not from the worktree itself".

**문제 1 — leak**: `git worktree prune`은 `.git/worktrees/` 메타데이터만 제거하고 실제 worktree 디렉터리(`~/.cache/autoqafix/<cid>/worktree`)는 남겨둠. 테스트가 여러 번 돌면 `~/.cache`가 누적됨 (현재 검증은 각 TEST가 자체 `T*_FIXTURE`로 격리되므로 영향 없음).

**문제 2 — `repo` 인자가 시그니처를 무거움**: `worktree`도 인자로 받으면 `wt = item.parent.parent` + `.parents` 루프 제거로 깔끔해짐 (review-2 P1 #2).

### D-2. `run_with_timeout` SIGTERM→SIGKILL 승급 (`autoqafix_core.py:210-248`)
**의도**: 우아한 종료 1초 대기 후 강제 종료. 운영 관점에서는 좋은 패턴.

**문제 — effective timeout**: SIGTERM(즉시) + wait 1s + SIGKILL + wait 2s + communicate 2s = 최악 +5s. TEST 3 (timeout=3s)는 최악 8s. verify는 150s 안이라 통과. 운영 timeout=10800s는 무관.

**문제 — silently drain**: `proc.communicate(timeout=2)` 실패 시 `proc.stdout, proc.stderr` 직접 read. `Popen`의 text 모드라 보통 None이거나 str. NoneType이면 dispatch의 `stderr.strip()`은 `AttributeError` → `except Exception: original_body = ""` 흡수. 표면은 OK지만 stderr 손실.

### D-3. `dispatch()`에서 `git reset --hard origin/main` 완전 제거
review-1 A-2의 첫 번째 증상(파괴적 reset)은 해결. 그러나 위 A-2 "남은 문제"가 새 크래시 경로를 만듦.

### D-4. FAKE_MODE 명시적 export (`verify-issue-16.sh:76`)
```bash
export FAKE_MODE="${FAKE_MODE:-ok}"
```
좋은 변경. 환경 누락 시 default `ok`로 명시.

### D-5. TEST별 stale state 정리 (`verify-issue-16.sh:152-153`, `:310-311`)
```bash
rm -rf "$STATE_DIR1/worktree" 2>/dev/null
```
이전 실행 잔재 정리. 운영엔 없지만 테스트 격리성 ↑.

## E. 권장 후속 절차

1. **A-3 즉시**: `cmd = ["bash", str(wrapper_dir / f"{wrapper}.sh"), "-p", ...]` — 프로덕션 즉사 버그.
2. **A-2 (남은 부분)**: success path를 `if not timed_out:`으로 완화하고 archive 존재로 판정. failure path 진입 전 `item.exists()` 확인.
3. **B-1·B-2 즉시**: UNTRACKED_DUMMY를 `run_autofix` **전**에 생성. TEST 4는 `autofix-1=fail, autofix-2=archive`로 순서 뒤집기.
4. **C-2·P1 #2·#3·#4·P2**: 다듬기 항목 일괄 정리.
5. **B-3·B-4**: `regression-tests/lib/fake-wrapper.sh` 사용, `/tmp` 출력은 TEST별 임시 파일, `pgrep`은 더 구체적 패턴.
6. **D-1의 leak**: worktree 디렉터리도 정리 (rmtree).
7. 위 수정 후 verify 재실행으로 4 시나리오 + UNTRACKED_DUMMY·TEST 4 순서 모두 PASS 확인.

## 검증 실행 기록 (2026-07-10, MiniMax-M3, 커밋 35886dd 기준)

```
=== TEST 1: FAKE_MODE=archive ===   4/4 PASS (UNTRACKED_DUMMY는 무의미한 검사, B-1)
=== TEST 2: FAKE_MODE=fail ===      4/4 PASS (A-1 해소 확인)
=== TEST 3: FAKE_MODE=hang ===      5/5 PASS (A-4 해소 확인, no zombie)
=== TEST 4: mixed ===               3/3 PASS (순서상 fail-then-계속을 검증하지 못함, B-2)
ALL TESTS PASSED  ← 표면
```

표면은 ALL PASSED이지만 **검증력이 빈 항목 3개**(B-1·B-2·B-3)와 **여전히 미해결된 프로덕션 즉사 버그**(A-3)가 남아 있으므로, "구현 완료"로 단정하면 안 됨. issue-16.md의 "검증 결과: ALL TESTS PASSED"는 **다소 낙관적**.

## 본 리뷰 한계 자인

- **qwen의 wrapper-exits-nonzero-after-archive 시나리오**를 실제로 재현하지는 못했음. 정적 분석 + 코드 흐름 추론으로 결론. 테스트 추가가 필요.
- **SIGTERM→SIGKILL 승급의 process group 동작**은 verify TEST 3의 "no zombie processes" PASS로 간접 확인. 자식 프로세스가 자체적으로 zombie를 만들지는 않았다는 의미일 뿐, 완전한 보장 아님.
- **production PATH 환경** 재현 못함 (테스트만 가능). A-3는 코드 grep + judge_tier 대조로 결론.