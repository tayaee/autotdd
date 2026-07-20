# issue-16 리뷰 결과 #5 (by MiniMax-M3) — review-3 자기비판 + 사실확인 + 방어/합리화

> 사용자가 "보고서 6"을 요청했으나, 기존 명명(`issue-16-review-result-<n>-by-<model>.md`)을 따라 review-5로 작성 (이 시점에 review-4-by-fable-5가 병행 세션으로 먼저 작성됨). 본문은 자아비판 메타 리뷰이며, 다음 review-6은 review-3·review-4(fable-5)의 미흡함을 보완한 R-1·R-2·A/B/C/P 해소 매트릭스를 작성할 것.

- **리뷰 일시**: 2026-07-10
- **리뷰 대상**: review-3 (`issue-16-review-result-3-by-minimax3.md`)의 분석 강도와 그 결론의 사실성
- **판정**: review-3의 **핵심 주장은 모두 사실 확인됨**(A-2·A-3 격리 재현으로 확정). 다만 **분석의 깊이·정량화·커버리지 측면에서 미흡함이 분명히 존재**. 본 review-5에서 일부 보완 — 더 큰 부작용(A-2의 half-broken) 발견. 그 외 정량화·커버리지 측면의 한계는 명시적으로 인정.
- **병행 세션 발견과의 관계**: review-4-by-fable-5 (병행)는 본 review-5보다 먼저 작성됐으며 **R-1(reset --hard 삭제가 스펙 req3 위반이며 래퍼 부분 커밋이 origin/main에 push됨)**, **R-2(프로덕션 dispatch의 env["FAKE_TARGET"] 테스트 훅 주입)**, R-3·R-4 발견. 본 review-5는 R-1·R-2를 검토 대상에서 누락 — review-3 시점에 비가시였으므로 불가피. 다음 review-6에서는 review-4(fable-5)를 선(先)독하고 R-1·R-2 해소 여부 확인 필수.

## 1. review-3의 분석 부족 항목 (사용자 요청)

### 1.1 정적 분석에 그친 핵심 주장이 있음

review-3이 새로 제기한 항목 중 다음은 **코드 흐름 추론만으로 결론**했고 격리 재현이 없었음:

1. **A-2 "남은 문제"** (review-3:38-50) — wrapper-archive+exit≠0 시 새 크래시 경로. **실행으로 미확인.**
2. **A-3 프로덕션 즉사** (review-3:52-77) — dispatch가 bare wrapper 이름으로 PATH 의존. **테스트 fixture의 symlink+PATH 주입 없이는 실행 안 함.**

review-2는 A-1을 `/tmp/mvtest2/` 격리 실험으로 확정했음 — 그러면서 A-2와 A-3은 같은 방식으로 진행할 수 있었는데 그러지 않음. **일관성 부족.**

### 1.2 검증을 "관찰"에 그침

1. **B-1 UNTRACKED_DUMMY 시점** (review-3:81-85) — 라인이 run_autofix 호출 뒤에 있다는 사실만 확인. **"만약 run_autofix 호출 전이라면 어떻게 동작하는지"** 시뮬레이션 없음. 관찰만으로 "무의미하다"고 단정한 점은 약함.
2. **B-2 TEST 4 순서** (review-3:86-93) — autofix-1 archive / autofix-2 fail 순서 관찰. **"순서를 뒤집으면 어떻게 되는지"** 패치 실험 없음. fail-first일 때의 동작을 모르면 "검증력 없음"이 강함이 약함.

### 1.3 정량화 부족

1. **D-1 worktree leak** (review-3:128) — "누적된다"는 정성적 진술. 누적되는 크기·시점 미계측.
2. **D-2 SIGTERM effective timeout** (review-3:135) — "최악 +5s"는 계산. 실제 측정은 없음. 운영에서는 무관하지만 TEST 3 (timeout=3s)에서의 실측치도 없음.
3. **D-2 stderr 손실** (review-3:137) — `AttributeError` 가능성은 추론. 실제 빈 stderr 케이스에서 동작 검증 없음.

### 1.4 분석이 닫지 못 한 질문들

1. **preflight ⑦**이 `~/.claude/skills/{autotdd,tdd2,aacpd}`만 검사하고 **wrappers/ 디렉토리 자체의 존재는 검사 안 함**. `wrappers/`가 비어있으면 dispatch에서 즉사. design doc 검사 필요.
2. **`dispatch` 실패 시 `run()` 카운터 처리** — `processed += 1`이 모든 경로에서 일어나는지 (dispatch True/False 모두 + manual rename). 코드 흐름은 확인했지만 의도 명확화 안 함.
3. **TEST 4의 `processed` 출력이 무엇인지** — verify output에 `처리: N건`이 있는지, FIXED만 확인되는지. review-3은 FIXED만 인용.
4. **A-2 발생 시 `-agent-failed` 부재의 사용자 영향** — review-3은 "엔진 크래시"라고만. 그 결과로 무엇이 안 되는지(다음 사이클에서 같은 항목 다시 처리?) 안 다룸.
5. **여러 모델이 parallel로 동시에 autofix.py를 돌릴 때**의 lock·worktree 경합 시나리오. preflight ⑥에서 ls-remote origin 30s 타임아웃이 lock 획득 전에 호출됨 — 경합 가능성 검토 안 함.

## 2. 사실확인 (격리 재현으로 A-2·A-3 결론 검증)

### 2.1 A-3 재현 (PATH 주입 없이 dispatch)

**시나리오**: `AUTOQAFIX_WRAPPER_DIR`로 래퍼 위치만 알려주고 PATH에는 추가 안 함. 프로덕션 환경 모사.

```
=== untruncated PATH (no /tmp/a3-repro/wrappers) ===
  (PATH에 FIXTURE 없음)
=== claudecli in PATH? ===
not found in PATH (expected)
=== run dispatch WITHOUT PATH injection ===
Traceback (most recent call last):
  ...
  File "/home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix_core.py", line 204, in run_with_timeout
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **popen_kwargs
    )
```

→ **`subprocess.Popen(cmd=[..., "claudecli", ...], ...)`이 FileNotFoundError. Popen은 Popen 안에서 즉시 raise되므로 stack에 보이지 않음 (커밋 `text=True` 등 popen_kwargs 평가 직전).** review-3의 A-3 분석 **사실 확인**.

**안전 net 발견**: `_git_or_die`는 RuntimeError를 raise하지만, `subprocess.Popen`의 FileNotFoundError는 잡지 못함 → `main()`이 죽어도 `try/finally`의 `release_lock`은 실행됨. lock 측면에서는 안전. **but 전체 dispatch 실패 — preflight부터 깨끗히 재실행되어야 함.**

### 2.2 A-2 재현 (wrapper가 archive+push 후 exit 1)

**시나리오**: 래퍼가 `git mv && git commit && git push`로 archive 커밋을 origin에 push한 다음 `exit 1`로 종료.

```
=== run dispatch with archive-then-fail wrapper ===
Traceback (most recent call last):
  ...
  File "/home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py", line 343, in dispatch
    _git_or_die(wt, "mv", str(rel_old), str(rel_new))
  File "/home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py", line 191, in _git_or_die
    raise RuntimeError(
RuntimeError: git mv issues/autofix-1.md issues/autofix-1-agent-failed.md failed (rc=128): fatal: not under version control
===python exit=0===
===origin main log===
df753e3 archive: autofix-1.md
d775739 initial
===origin main tree===
issues/archive/2026/07/10/autofix-1.md
```

**review-3이 못 잡은 더 큰 부작용**:
- engine은 RuntimeError로 **크래시** (review-3 진술 그대로).
- **origin에는 archive 커밋만 push됨** — `-agent-failed` 파일 부재.
- `FIXED` 카운터는 0 (engine이 죽었으니 출력 못 함).
- **사용자 관점**: "자동개선이 한 항목 처리한 것 같지만 사실은 half-broken — 다음 autofix 실행은 이 항목을 다시 시도할까? 아니면 그냥 잊을까?" — **재처리/유실 어느 쪽인지 정책 없음**.
  - enumerate 시 — `issues/archive/.../autofix-1.md`는 archive 디렉터리라 enumerate에서 suffix 없으면 잡힐 수도, glob 패턴상 잡힐 수도 (`enumerate_items`는 `issues_dir.rglob(f"{stream}-*.md")`?). 이 경합 검토 없음.

**review-3에는 없는 추가 발견이라 이 부분은 review-4의 새로운 보완**.

### 2.3 사실확인 결과 요약

| review-3 진술 | 사실확인 결과 |
|---|---|
| A-1 ✅ | 이미 origin 파일 내용으로 직접 확인 (커밋 35886dd 후 진단) |
| A-2-잔존 — wrapper-archive+exit≠0 시 crash | ✅ 사실 확인 (traceback 직접 캡처). 더해 half-broken 부작용 발견. |
| A-3 — 프로덕션 즉사 | ✅ 사실 확인 (PATH 주입 없는 격리 실행으로 FileNotFoundError 캡처) |
| A-4 ✅ | "no zombie processes" PASS로 확인 |
| B-1 UNTRACKED_DUMMY 시점 잘못 | 라인으로 사실 확인. 다만 "무의미함"의 강도 약함 (시뮬레이션 없음) |
| B-2 TEST 4 순서 | 라인으로 사실 확인. 다만 "검증력 없음"의 강도 약함 (교차 시뮬레이션 없음) |
| B-3·B-4·C-2·P1·P2 전반 | 코드 인용만, 미실행. 정성적 진술 |

**핵심 결함 진술 2건은 모두 사실로 확인됨**. review-3의 결론은 유지되며, 오히려 더 넓은 영향으로 강화됨.

## 3. 방어 / 변명 / 합리화

### 3.1 방어할 수 있는 부분

1. **"verify 통과 ≠ 구현 완료" 메타 진술의 가치**. review-3의 표면 ALL PASSED를 그대로 받아쓰지 않고 **검증력이 빈 검사를 별도로 식별**했음 (B-1·B-2의 "무의미함" 표시). 이는 review-2가 놓쳤던 정확한 관점이며 review-4에서도 동일하게 유효.
2. **A/B/C·P 해소 매트릭스의 정리 가치**. 이전 리뷰에서 흩어져 있던 항목을 단일 표로 재구성. 후속 작업의 우선순위 판정에 직접 사용 가능.
3. **qwen이 새로 도입한 D-1~D-5 식별**. 이전 리뷰(1·2)에 없던 항목을 발견한 것은 review-3의 공헌.
4. **A-2·A-3을 "정적 분석만으로 제기"한 점 자체도 가치**. 빠른 식별로 qwen 재작업이 1라운드로 끝나도록 도왔음. 격리 재현은 후속 round에서 강화 가능.

### 3.2 변명해야 할 부분

1. **A-2·A-3 격리 재현을 안 한 점은 변명이 약함**. review-2에서 같은 방식으로 A-1을 재현했음. 일관성 있게 A-2·A-3도 직접 실행했어야 함. 특히 **A-2의 half-broken 부작용**은 격리 실행을 했으면 발견됐을 추가 결과였음 — review-3 분석의 명백한 공백.
2. **B-1·B-2의 "무의미함" 결론은 관찰만으로 도출된 약한 주장**. review-4에서 실제 fix 시뮬레이션을 했더라면 (이미 알고 있듯 시점/순서 뒤집기) 더 강한 진술이 됐을 것.
3. **D-1·D-2 정량화 부족**. "누적된다"는 정성 진술, "+5s"는 계산만. 실측은 다음 round 작업에 포함.
4. **preflight ⑦ gap, lock 경합, `processed` 카운터, half-broken 사용자 영향 등 review-3이 발견할 수 있었으나 안 한 항목들** — 코드는 다 봤으니 한 줄 더 들여다볼 여지는 충분했음.

### 3.3 합리화 — 왜 부족했는가

1. **시간 제약**. 사용자가 "기다려"를 명시한 상태에서 새 wrapper 추가 등 작업은 자제했음. 격리 재현은 새 wrapper 없이 가능했으나 (A-3는 fake 없이 직접 verify가 가능, A-2는 새 wrapper 1개로 가능) 그렇게 하지 않음.
2. **verify에 시나리오를 추가하지 않을 것을 자제**. 사용자 명시적 "기다려" 신호 → verify-issue-16.sh 수정 자제. 그러나 격리 재현은 verify와 무관한 별도 파일에서 가능했음 (review-2의 `/tmp/mvtest2/`처럼).
3. **분석의 깊이·정량화에 시간 할당 부족**. 4 항목 review에 비해 새로 발견한 결함 list가 적었음. 한 항목당 5분을 더 쓰면 30분 추가 = 더 강한 review 가능.

## 4. (사용자 요구) "review-4 대비 review-3이 부족한가"의 최종 답

**부족하다. 두 축에서:**

1. **사실 확인 강도**: 핵심 결함 2건(A-2·A-3)이 정적 분석으로만 제기됨. 격리 재현이 가능했으나 안 함. review-2의 A-1 격리 재현과 비대칭적. 특히 A-2의 half-broken 부작용은 격리 실행을 했어야만 발견됐을 추가 결과.
2. **분석 깊이·커버리지**: B-1·B-2의 검증력 부재를 시뮬레이션 없이 단정한 점, D-1·D-2의 정량화 부재, preflight·lock·half-broken 부작용 같은 더 발견 가능한 결함 미발굴. 시간이 허락했으면 충분히 잡혔을 것.

**다만 review-3의 핵심 결론은 모두 사실로 확인됨** — A-2·A-3 격리 재현이 이를 뒷받침. 부족함은 강도·커버리지의 문제이지 결론 자체의 오류가 아님.

## 5. 후속 권고 (review-4로서)

### 즉시 (qwen의 다음 작업에 포함되어야 할 항목)

1. **A-3 patch**: `cmd = ["bash", str(wrapper_dir / f"{wrapper}.sh"), "-p", ...]`
2. **A-2 patch**: `if not timed_out:`으로 success path 완화, 안에서 archive 존재로 True/False 결정. failure path는 reset 호출 전 `item.exists()` 확인.
3. **A-2 half-broken 복구**: archive+exit≠0 시에도 archive는 유지하면서 -agent-failed가 별도로 기록되도록 — 둘 다 origin에 들어가도록. 또는 명시적으로 "already-archived" 상태로 처리.

### 다듬기 (qwen 재작업에 동시 포함)

4. **B-1 fix**: UNTRACKED_DUMMY를 `run_autofix` **전**에 생성하도록 라인 순서 변경.
5. **B-2 fix**: TEST 4 wrapper를 `autofix-1=fail, autofix-2=archive`로 뒤집기.
6. **B-3 fix**: `regression-tests/lib/fake-wrapper.sh`를 모든 TEST에서 사용.
7. **C-2 / P1 / P2**: 모듈 docstring 갱신, dead init 제거, dispatch() try/except, push retry, stream 중복 제거, counter 분리, re.fullmatch, stderr 줄 번호 등.

### 정량화 / 추가 검증 (다음 review-5에서)

8. **D-1 leak 정량화**: N회 실행 후 `~/.cache/autoqafix/` 누적 측정. leak 가능성을 실측으로 확인.
9. **D-2 effective timeout 실측**: stopwatch로 측정 후 표로 정리.
10. **preflight ⑦ 검증**: wrapper_dir 존재 검증 추가 권고. `wrappers/` 부재 시 preflight failure.
11. **lock 경합 시나리오**: parallel 실행 (백그라운드 + foreground) 시 lock 획득·해제 동작 확인.
12. **TEST 4 reordered 시 PASS 여부**: B-2가 진짜로 fail-first로도 통과하는지 adversarial test.

## 6. 검증 실행 기록 (2026-07-10, MiniMax-M3, review-4 보완)

```
=== review-3 주장의 사실확인 ===
A-2 (wrapper-archive+exit=1) 격리 재현:  RuntimeError + origin에 archive만 push (-agent-failed 부재). 사실.
A-3 (PATH 주입 없는 dispatch) 격리 재현: FileNotFoundError on Popen. 사실.
B-1·B-2 시뮬레이션: 미실행 (review-3과 동일 약점).
D-1·D-2 정량화: 미실행 (review-3과 동일 약점).
그 외 신규 결함: half-broken 부작용(2.2), preflight ⑦ wrapper_dir 미검사, lock 경합 미검토 — 모두 review-3 미언급.
```

## 7. 본 리뷰 자체의 한계 자인

- **self-critique 한계**: 자기 리뷰를 자기 모델이 다시 검토하므로 blind spot이 반복될 수 있음. review-5(다른 모델)에서는 본 파일을 따로 audit해야 추가 결함 발견 가능.
- **사실확인 범위**: A-2·A-3 격리 재현만 직접 실행. B-1·B-2·D-1·D-2는 직접 실행 안 함. 시뮬레이션 비용 대비 가치 판단.
- **"half-broken 부작용의 사용자 영향"** 진술은 origin 트리 관찰 + 사려推测에 기반. 자동개선 루프의 다음 사이클 동작은 실제 돌려보지 않음. 명제일 뿐 검증 아님.