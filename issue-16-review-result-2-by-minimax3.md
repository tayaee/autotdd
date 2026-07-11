# issue-16 리뷰 결과 #2 (by MiniMax-M3)

- **리뷰 일시**: 2026-07-10
- **리뷰 대상**: main(1bbf179) 위의 미커밋 작업본 — `autofix.py` dispatch 실구현,
  `autoqafix_core.py` `run_with_timeout` cwd 추가, `regression-tests/verify-issue-16.sh`
- **판정**: 구현 미완료. `verify-issue-16.sh` 실행 시 TEST 2 실패, TEST 3 미실행.
  승인 기준 5개 중 1개만 통과. qwen 재작업 대상.
- **선행 이력**: 리뷰 #1(fable-5, 1차)이 A-1~A-4 + B·C를 잡음. 본 리뷰는
  #1과 독립으로 진행했으나 결과를 비교·교차검증함. 본 리뷰가 새로 찾은 결함은
  없으나, A-1의 재현 증거를 격리 실험으로 확정함. **A-2/A-3/A-4는 #1에 이미
  기록되어 본 리뷰에서 놓친 항목**이므로 qwen 재작업 시 #1과 본 파일을 함께
  참고해야 함.

## 격리 실험으로 확정한 사실

### 1. A-1 재현 (`/tmp/mvtest2/`)
```
echo hello > a.txt && git add a.txt && git commit -q -m initial
echo world >> a.txt           # 미커밋 수정
git mv a.txt b.txt             # ← rename만 스테이징, 수정은 누락
git commit -q -m rename
git show HEAD:b.txt            # 결과: "hello"만 (world 누락)

# 해결책: git add a.txt  ← 이걸 먼저 하면 world가 보존됨
```
git의 `mv`+index 갱신 동작이 rename과 콘텐츠 변경을 합치지 않는 한계를 격리로
확정. autofix.py의 `item.write_text(body)`(B) → `_git_or_die(wt, "mv", ...)`(C)
사이에 `git add`가 없으므로 (C)가 rename만 커밋하고 (B)의 수정이 누락됨.

### 2. A-1 직접 관찰 (TEST 2 진단 실행)
`issues/autofix-1.md` 원본:
```
# autofix-1: fail test
agent-tier: local-ok
reported-by: ...
## 배경
fail mode 테스트.
```
같은 코드를 두 번 다른 시점에 실행하여:
- **worktree의 `autofix-1-agent-failed.md`**: `## agent 실패 기록` 섹션과 레코드(claudecli, exit 1)가 **존재**
- **origin의 `autofix-1-agent-failed.md`** (push 후): `## agent 실패 기록` 섹션 **없음**

이 비대칭이 A-1의 결정적 증거 — worktree엔 있고 origin엔 없는 것은 (B)의
수정이 commit 단계에서 누락됐다는 뜻이다.

### 3. verify-issue-16.sh 실행 결과 (2026-07-10, 120초 타임아웃)
```
=== TEST 1: FAKE_MODE=archive ===   4 PASS / 0 FAIL
=== TEST 2: FAKE_MODE=fail ===      2 PASS / 2 FAIL
                                    ↑ ## agent 실패 기록 section missing
                                      wrapper name missing from 실패 기록
=== TEST 3: FAKE_MODE=hang ===      (멈춤 — A-4가 원인, #1에서 식별)
=== TEST 4: mixed ===               (실행 안 됨)
exit=124 (timeout)
```

TEST 2의 두 FAIL은 A-1로 설명된다. TEST 3 hang은 #1이 잡은 **A-4**
(`verify-issue-16.sh:76-78`의 `eval "$extra_env"`가 export하지 않아
`AUTOQAFIX_IMPL_TIMEOUT=3`이 자식 python에 전달 안 됨 → 기본 10800초 경로로
빠져 fake-wrapper의 `sleep 600`을 통째로 기다림) 때문이며, 본 리뷰는 이 원인을
놓쳤다.

## 본 리뷰에서 도출한 품질/구조 항목 (P0/P1/P2)

#1의 A/B/C 항목과 중복되지 않는 본 리뷰 관점의 개선안:

### 🔴 P0 — 즉시 수정 (코드 정확성)

1. **`dispatch()` 실패 경로의 `git mv` 전 `git add` 누락** (autofix.py:333-340)
   — #1의 A-1과 동일. 격리 재현으로 확정.
   ```python
   rel_old = item.relative_to(wt)
   _git_or_die(wt, "add", str(rel_old))          # ← 추가
   _git_or_die(wt, "mv", str(rel_old), str(rel_new))
   ```
   또는 더 안전하게 — rename과 기록 추가를 두 커밋으로 분리:
   ```python
   _git_or_die(wt, "add", str(rel_old))
   _git_or_die(wt, "commit", "-q", "-m", f"{stem}: 실패 기록 추가")
   _git_or_die(wt, "mv", str(rel_old), str(rel_new))
   _git_or_die(wt, "commit", "-q", "-m", f"{new_path.stem}: agent 실패 — {detail}")
   ```

### 🟡 P1 — 1차 품질 개선

2. **사뿐 초기화 코드 제거** (autofix.py:258)
   ```python
   wt = item.parent.parent  # ← L258에서 즉시 덮어쓰는 dead 초기값
   for ancestor in item.parents:
       ...
       wt = ancestor
       break
   ```
   `run()`이 이미 `worktree`를 알고 있으니 인자로 받으면 루프와 dead 초기값
   모두 사라진다. `dispatch(item, wrapper, stream)` → `dispatch(item, wrapper,
   worktree)`로 변경하고 `n`은 `item.stem.partition("-")`로 derive.

3. **`dispatch()` 예외 누수**: `_git_or_die`가 `RuntimeError`를 raise하면
   `run()` 루프 전체가 중단됨. "실패해도 다음 항목 계속" 요건과 충돌.
   `try/except RuntimeError`로 흡수하고 카운터(`failed_internal`)에 기록.

4. **push 실패 시 재시도 부재**: `finalize_item`(issue-11)이
   `pull --rebase` 후 재push하는 패턴이 dispatch에도 필요.

### 🟢 P2 — 다듬기

5. `dispatch()`의 `cmd` 조립이 `stream`/`n`을 인자로 받는 중복 — `item.stem`
   사용으로 정리.

6. `run()`의 `processed` 카운터가 `dispatched + renamed-to-manual`을 합산 —
   의도 불명확. 분리 권장.

7. `re.fullmatch()` 사용 (현재 `re.match()`만으로 시작 매치).

8. stderr "마지막 3줄" 캡처 시 빈 줄이 strip으로 사라짐 — 줄 번호 명시
   권장 (`stderr@L42-44:` 등).

## #1 리뷰 대비 본 리뷰의 공헌과 한계

- **공헌**: A-1을 격리 실험으로 재확인 (git mv의 rename-only 스테이징 한계
  직접 증명). worktree vs origin 비대칭 관찰로 가설 확정.
- **한계**: #1이 식별한 A-2(archive+exit≠0 시 reset이 항목 소멸), A-3(wrapper
  PATH 의존), A-4(env 미export → TEST 3 hang) 중 **A-4를 놓침**. 본 리뷰가
  TEST 3 hang을 "별도 진단 필요"로 끝낸 것은 #1의 A-4를 인용하지 못한 결과.
  다음 리뷰부터는 사전 검토 자료로 #1을 먼저 읽는 절차가 필요.

## 권장 후속 절차

1. #1 A-1·A-2·A-3·A-4 + #2 P0·P1을 모두 반영한 패치를 qwen이 작성
2. `verify-issue-16.sh`에 #1의 B-1·B-2(UNTRACKED_DUMMY 시점, TEST 4 순서)
   수정 반영 — fake-wrapper 확장은 issue-18의 `regression-tests/lib/fake-wrapper.sh`
   사용으로 (#1 B-3)
3. 재실행으로 전 항목 PASS 확인
4. 이슈 파일 구현 결과 섹션 기입
5. 본 리뷰 #3에서 PASS 검증 후 종료 판정

## 검증 실행 기록 (2026-07-10, MiniMax-M3)

```
=== TEST 1: FAKE_MODE=archive ===   4/4 PASS
=== TEST 2: FAKE_MODE=fail ===      2/4 PASS (A-1, ## agent 실패 기록·래퍼명 누락)
=== TEST 3: FAKE_MODE=hang ===      미완 (timeout 120s, #1 A-4 원인)
=== TEST 4: mixed ===               미실행
exit=124
```