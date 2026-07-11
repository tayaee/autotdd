# issue-20-review-result-3-by-minimax3

## 메타

- **대상 커밋**: `029ce34 issue-20: autoqafix-doctor — 사전 점검 도구 (preflight 상위 집합 + 래퍼/usage/select-llm/deploy/뮤텍스/스킬 진단, --ping)`
- **리뷰 일시**: 2026-07-11
- **리뷰어**: minimax3 (3차 self-audit)
- **직전 리뷰**: 1차 `issue-20-review-result-1-by-qwen.md` (qwen, 2026-07-11). 본 3차는 1차의 부족한 분(qwen이 못 잡은 P0/P1)과 qwen 판단에 대한 합치/불합치를 정리한다.
- **검증**: `bash regression-tests/verify-issue-20.sh` → 15/15 PASS. 전체 회귀 17/17 PASS.
- **실행 재현**: 임시 픽스처 repo + doctor 직접 호출로 13가지 엣지 검증 (P0-1, P0-2, P1-1, P1-4, P2-3, P2-4 포함).
- **이 리뷰 작성 시 학습 위반**: `ls`로 기존 번호 확인을 **저장 후에야** 했다. 메모리([[issue-16-qwen-review-cycle]] 교훈 1) "사전에 직전 리뷰를 모두 읽지 않으면 놓치는 버그가 있다"를 그대로 답습했다. qwen이 본 11건 중 3건은 본 self-audit이 동의하지 않음 (qwen 오판), 2건은 qwen이 놓침 (본 self-audit이 보강), 6건은 합의.

## 요약

issue-20 구현은 스펙을 전반적으로 충족하나 **2건의 P0**(잠금 파일 비정상 시 doctor 자체가 traceback으로 크래시 + exit 0), **P1 다수**(잠금 staleness 정책 drift, lock 검증 커버리지 0%, deploy glob 스펙 drift, 빈 env silent 통과 등), **P2 다수**(중첩 uv, 사설 API 사용, run_pings 폴백, 빈 AUTOQAFIX_WRAPPERS 등)가 있다.

qwen 1차 리뷰는 P0-1·P1-1·P2-1·T1-2·T1-3 등을 정확히 짚었지만, **P0-2(잠금이 디렉터리)** 와 **P1-1(stale 시 AUTOQAFIX_LOCK_STALE_SEC 미적용)** 와 **P1-2(lock 검증 0% 커버리지)** 를 놓쳤다. 반대로 **P1-3(env var 미전파)**, **P1-4(select-llm exit code 무시)** 는 qwen이 본 self-audit과 반대로 본 self-audit이 동의하지 않는다 (각각 정상 동작/스펙 의도). 그리고 **P1-2(REQUIRED_SKILLS에 tdd 추가)** 는 qwen이 "중복/모호"라고 평했지만, issue-20.md:22 스펙이 명시적으로 4개를 요구하므로 의도된 확장으로 본다.

## 1. qwen 1차와 합의하는 항목

qwen이 본 11개 중 6개를 본 self-audit도 그대로 인정:

- **P0-1**: `check_lock` — `int(info.get("pid") or "0")`의 silent coercion. 재현으로 확인 (출력 traceback + exit 0).
- **P1-1 (qwen) / P1-4 (본)**: `deploy-to-*` glob — 스펙은 `deploy-to-env.{sh,ps1,bat}`이지만 구현은 `deploy-to-*`. qwen은 "dead code"라 표현, 본 self-audit은 "spec drift"로 표현. 같은 코드 위치 (`autoqafix-doctor.py:135`). 수정안 합의: glob을 `deploy-to-env.{ext}`로 좁히거나 의도를 코멘트로 명시.
- **T1-2 / P2-4**: 빈 `AUTOQAFIX_WRAPPERS`가 silent 통과 — 재현으로 확인 (WARN 출력 없이 FAIL 0).
- **T1-3**: `select-llm.py` 부재 테스트 누락 — 본 self-audit도 동의.
- **P2-1 (qwen) / P2-3 (본)**: `run_pings`의 `WRAPPER_DEFAULT_DIR` 하드 폴백 — 본 self-audit도 동의.

## 2. qwen 1차가 놓친 항목 (3차 보강)

### P0-2: `check_lock` — 잠금 파일이 디렉터리일 때 uncaught `IsADirectoryError`

**qwen 1차 누락**. qwen은 P0-1(`pid` 파싱)만 잡고, 같은 `_read_lock` 경로의 다른 입력 비정상은 보지 못함.

**재현**:

```bash
mkdir "$tmp/work/.git/autoqafix.lock"   # 파일이 아니라 디렉터리
bash autoqafix-doctor.sh --repo "$tmp/work"
```

**출력 (마지막)**:

```
OK select-llm (qwencli)
Traceback (most recent call last):
  ...
IsADirectoryError: [Errno 21] Is a directory: '.git/autoqafix.lock'
```

**원인**: `core._read_lock` (`autoqafix_core.py:121`)이 `path.read_text()`로 무조건 읽음. `OSError` 미처리.

**영향**: P0-1과 동일하게 "진단 완료" 푸터 미출력, `exit 0`로 정상 종료 가장. 프로덕션 시나리오 — `acquire_lock`이 디렉터리를 못 지우는 race (디렉터리는 `unlink`로 못 지움). 권장 수정: P0-1과 묶음 (둘 다 `_read_lock`을 try/except로 감싸고 `dict | None` + 에러 시 WARN/FAIL 결정).

### P1-1 (3차): `check_lock`이 `AUTOQAFIX_LOCK_STALE_SEC`를 무시함 (정책 drift)

**qwen 1차 누락**. qwen은 `acquire_lock`의 stale 정책 자체를 짚지 못함.

`autoqafix_core.acquire_lock`은 **두 조건** 중 하나면 잠금을 회수(reclaim)한다 (`autoqafix_core.py:140-154`):

```python
stale_sec = int(os.environ.get("AUTOQAFIX_LOCK_STALE_SEC", str(DEFAULT_LOCK_STALE_SEC)))  # default 4h
...
is_stale = age_sec is not None and age_sec > stale_sec
if not (pid_dead or is_stale):
    return False
# (else) reclaim
```

반면 `autoqafix-doctor.py:check_lock`은 `pid_dead`만 본다 (149–152행):

```python
same_host = info.get("host") == socket.gethostname()
pid_dead = same_host and not core._pid_alive(int(info.get("pid") or "0"))
if pid_dead:
    d.ok("뮤텍스 잠금 없음 (stale lock — ...)")
else:
    d.fail("뮤텍스 잠금", ...)
```

**재현** (다른 호스트 + 5년 전 start):

```bash
cat > "$tmp/work/.git/autoqafix.lock" <<'L'
host=different-host-xyz
pid=99999
role=qa
start=2020-01-01T00:00:00+00:00
L
bash autoqafix-doctor.sh --repo "$tmp/work"
```

**출력**:

```
FAIL 뮤텍스 잠금
[원인] 이미 qa이 실행 중 (different-host-xyz, 2020-01-01T00:00:00+00:00)
[조치] 실행 종료를 기다리거나, 확실히 죽었으면 .git/autoqafix.lock 삭제
```

5년 전 start인데도 FAIL. 실제 `acquire_lock`은 회수했을 것 (`is_stale=True`). **잘못된 FAIL**로 사용자 행동("`.git/autoqafix.lock 삭제`")을 유도.

**기대 동작**: stale 검사에 `AUTOQAFIX_LOCK_STALE_SEC` 반영 → `OK 뮤텍스 잠금 없음 (stale — start > 4h, 회수 가능)`.

**수정안**: `core.is_lock_reclaimable(path) -> bool` (또는 `peek_lock_with_reason(path) -> ("fresh"|"same_host_dead"|"cross_host_stale"|"alive", info)`) 추출 → doctor/autoqa/autofix가 동일한 정책으로 진단.

**부차 발견**: `autoqa.py:31-38`, `autofix.py:435-436`도 같은 패턴 (각자 `_read_lock` 후 진단만 출력, `acquire_lock`은 별도 호출). autofix/autoqa는 실제 `acquire_lock`을 다시 호출하므로 사용자 진단 메시지만 틀릴 뿐 실제 실행은 정상이지만, **doctor는 진단만 보고하므로 직접적 오진**.

### P1-2 (3차): `verify-issue-20.sh`의 lock 검증 0% 커버리지

**qwen 1차 누락**. qwen은 T1-1·T1-2·T1-3 (빈 env, select-llm 부재 등)만 짚고 lock 검사 자체의 부재를 명시적으로 거론하지 않음.

verify-issue-20.sh의 8개 시나리오 중 `check_lock` (⑥) 관련 **0개**:

| 시나리오 | 현재 |
|---|---|
| 잠금 없음 (기본 happy path) | ❌ 안 봄 |
| 동일 호스트 + 살아있는 pid → FAIL | ❌ 안 봄 |
| 동일 호스트 + 죽은 pid → OK (stale) | ❌ 안 봄 |
| 다른 호스트 + start < 4h → FAIL | ❌ 안 봄 |
| 다른 호스트 + start > 4h → OK (stale) | ❌ 안 봄 |
| 비정상 `pid` (영숫자, 빈 문자열) | ❌ 안 봄 (**P0-1 회귀 미탐지**) |
| 잠금이 디렉터리 | ❌ 안 봄 (**P0-2 회귀 미탐지**) |
| 빈 잠금 파일 | ❌ 안 봄 |

표면 15/15 PASS지만, **lock 검사 자체가 0번 실행된 검증을 "PASSED"로 가장한 빈 검사**. [[issue-16-qwen-review-cycle]] 교훈 2 ("verify가 PASSED여도 검증력이 빈 검사가 섞여 있으면 '구현 완료'로 단정하면 안 된다")와 정확히 같은 함정. **이 함정에 P0가 살고 있다** — P0-1·P0-2 모두 잠금 파일의 비정상 입력이 트리거인데, 잠금 파일을 만드는 테스트가 없으니 회귀 시 자동 미탐지.

### P1-3 (3차): `verify-issue-20.sh`의 wrapper 확장자 검증 1/3

qwen은 T1-1에서 ping 테스트의 FAKE_MODE 전파 불명을 짚었지만, `check_wrappers`의 `.sh`/`.ps1`/`.bat` 3종 확장자 중 `.sh`만 테스트된 사실은 짚지 않음. 본 self-audit 재현: `.ps1` 단독 wrapper, `.bat` 단독 wrapper 모두 OK로 정상 동작하긴 하나, **verify는 `.sh`만 봄**.

수정안: `fake_dir/<name>.ps1`만 두고 doctor를 호출 → `OK 래퍼 <name>` 기대 (PASS 시 회귀 잠금).

## 3. qwen 1차와 불일치하는 항목 (qwen 오판으로 판단)

### qwen P1-2 vs 본 self-audit: `REQUIRED_SKILLS = ("autotdd", "tdd2", "acpd", "tdd")`

**qwen 1차 주장**: "tdd는 preflight에 포함되지 않지만 doctor는 필수로 체크한다. 의도된 확장인지 명확하지 않음."

**본 self-audit 판단**: qwen 오판. **issue-20.md:22 스펙이 명시적으로 4개를 요구**:

```
⑦ ~/.claude/skills/{autotdd,tdd2,acpd,tdd} 존재
```

`autoqafix_core.py:93-96`의 preflight가 3개만 보는 것은 issue-10의 좁은 정의이고, issue-20이 4개로 확장한 것. README.md:22도 `autotdd` 스킬이 `tdd` 스킬을 의존한다고 명시 (`Matt Pocock's tdd skill`). 즉 doctor가 `tdd`를 추가한 것은 **스펙 의도**이며, preflight의 미반영이 잠재적 후속 이슈. 합리적 분리.

### qwen P1-3 vs 본 self-audit: env var 전파

**qwen 1차 주장**: "`run_with_timeout`이 `env=None` 시 부모의 env를 상속하지만, 테스트 픽스처에서 `AUTOQAFIX_WRAPPER`를 설정해도 usage 스크립트에 전달되지 않을 수 있다."

**본 self-audit 판단**: qwen 오판. `subprocess.Popen`의 기본 동작은 **부모 env를 상속**한다 (`env=None`이 명시적 디폴트). `run_with_timeout` (`autoqafix_core.py:182-233`)은 `env` 파라미터가 `None`일 때 그대로 `subprocess.Popen`에 넘기므로 부모 env 자동 상속. **verify-issue-20.sh가 `PING_WRAPPER="$LIB/fake-wrapper.sh"`로 ping-claudecli.sh를 통해 fake-wrapper에 전달하는 것이 그 증거** — env var 전파가 정상이라 가능.

단, qwen 우려의 부분 정합: 사용자가 doctor 호출 시 명시적으로 `env=...`을 좁히고 싶을 때(예: PATH를 격리하고 싶을 때) doctor는 그 방법을 제공하지 않는다. 다만 현재 use case에서는 부모 env 상속이 올바른 동작이고, 격리가 필요한 시나리오는 autoqafix 스위트 외부.

### qwen P1-4 vs 본 self-audit: select-llm exit code 무시

**qwen 1차 주장**: "select-llm.py가 exit 1 (오류)로 종료했지만 stdout에 우연히 wrapper name이 있으면 OK로 판정된다. exit code 1은 '선택 실패'를 의미하므로 false positive."

**본 self-audit 판단**: qwen 오판. **doctor:118의 주석이 명시**:

```python
# exit 2 = "none" 정상 경로 (issue-9) — 출력으로만 판정한다.
```

`select-llm.py` 디자인 (`select-llm.py:155-162`):

```python
if selected is None:
    print("none")
    sys.exit(2)   # ← 명시적 exit 2 for "none"
print(selected)   # exit 0 for selected
```

`exit 2`는 "none"의 정상 경로. 그 외 비정상(exit 1 등)은 처리하지 않음 (예외 시 uncaught). 따라서 **stdout만 검사하는 것은 의도된 디자인**. qwen의 "exit 1도 봐야 한다"는 주장은 정확하지만, **실제 exit 1은 stderr에 `[경고]`를 출력** (`select-llm.py:60-77`)하며 사용자에게 자연 노출됨. doctor가 stderr을 무시하는 게 거슬리지만 "false positive"라기엔 출력 경로가 있다. 본 self-audit은 doctor가 stderr을 WARN 라인으로 변환하는 정도를 minor 개선으로 권장 (qwen 주장보다 약한 권장).

### qwen P2-2 (commit message 모호) — 합치, 단 본질 아님

qwen의 "commit message에 'fixed' 명시 또는 코드에 주석 추가"는 cosmetic. doctor 코드의 `any(... for ext in ...)` 자체는 정확히 동작하므로 (Python 3 `any()`는 lazy) 큰 문제 아님. 다만 issue-20.md:51의 "구현 중 잡은 버그: any(glob제너레이터)..." 기록이 미래의 reader에게 혼란을 줄 수 있다는 qwen 지적은 유효.

## 4. qwen 1차 동의 + 본 self-audit 추가 (P2 / 안일함)

### P2-1 (3차): 중첩 `uv -q run` — 콜드 3.7s / 웜 1.4s

doctor 호출 체인:
- `autoqafix-doctor.sh` → `uv -q run autoqafix-doctor.py`
- doctor → `uv -q run usage-<name>.py` × N
- doctor → `uv -q run select-llm.py`
- select-llm → `uv -q run usage-<name>.py` × N (중복!)

기본 3 wrapper: doctor 자체 1 + usage 3 + select-llm 1 + select-llm 내부 usage 3 = **8회 직렬 uv 실행**. 사전 점검 도구치고 느림.

수정안:
- (a) doctor 안에서 usage를 `subprocess.run([sys.executable, str(script)])`로 직접 실행 (PEP-723 메타데이터 무시, sys.executable 사용). 외부 의존 없는 스크립트는 즉시 실행.
- (b) select-llm도 `import select_llm`으로 직접 호출. 단 PEP-723 격리 깨짐 → (a)가 무난.

### P2-2 (3차): 사설 API (`_lock_path`, `_read_lock`) 직접 사용

qwen은 못 짚음. doctor:145, autoqa.py:31-32, autofix.py:435-436가 모두 `core._lock_path`/`core._read_lock` 직접 호출. `_` 접두사 컨벤션을 어김. 수정안: `core.peek_lock(repo) -> dict | None` (public), 통일 사용.

### P2-3 (3차): 빈 `AUTOQAFIX_WRAPPERS` silent 통과 — qwen T1-2와 동일, 본 self-audit 재현으로 확정

qwen T1-2를 본 self-audit이 직접 재현:

```bash
AUTOQAFIX_WRAPPERS="" bash autoqafix-doctor.sh --repo <valid>
# → 진단 완료: FAIL 0건 (wrapper/usage 검사 자체가 안 일어남)
```

`os.environ.get("AUTOQAFIX_WRAPPERS", WRAPPERS_DEFAULT)` — env가 빈 문자열이면 default로 안 가고 빈 문자열 사용. `parse_wrapper_spec("")` → `{}` → `names = []` → `check_wrappers`/`check_usage_scripts` 루프 무실행. `check_select_llm`만 `OK select-llm (none)` 출력. **사용자는 wrapper 검사 통과로 오해 가능**.

수정안: `os.environ.get("AUTOQAFIX_WRAPPERS") or WRAPPERS_DEFAULT` (빈 문자열을 default로 fallback) + 그래도 빈 값이면 `WARN — AUTOQAFIX_WRAPPERS가 비어있음`.

### P2-4 (3차): `check_lock`이 lock_path 자체 부재 시 `info is None`만 처리 — 빈 파일/garbage 시 ungraceful

qwen P0-1의 pid 파싱 외, `_read_lock`의 동작 분석:

```python
def _read_lock(path: Path) -> dict[str, str] | None:
    try:
        content = path.read_text()
    except FileNotFoundError:
        return None
    data: dict[str, str] = {}
    for line in content.splitlines():
        if "=" in line:
            ...
    return data
```

- 빈 파일 → `data = {}` → `info.get("pid") or "0"` = `"0"` → `int("0")=0` → `_pid_alive(0)=False` → `pid_dead=True` → "stale" OK. **정상 동작** (확인됨).
- garbage 라인 → `data = {}` → 위와 동일 → stale OK. **정상 동작**.
- 디렉터리 → `IsADirectoryError` (P0-2). **크래시**.
- pid=not_a_number → `int("not_a_number")` ValueError (P0-1). **크래시**.
- pid=empty (예: `pid=`) → `info.get("pid")` = `""` → `"" or "0"` = `"0"` → 정상. **정상 동작**.

즉 P0-1 (pid 비정상) + P0-2 (디렉터리)만 크래시. P2-4 항목은 본 self-audit 검증 결과 정상 — 삭제.

## 5. 본 self-audit만 보는 새 항목 (qwen 1차 외)

### P2-5 (3차): `autoqafix-doctor.bat`의 `pause` 비대칭 — verify는 위치 무관

```bat
if %ERRORLEVEL% neq 0 (
    echo [원인] uv 없음
    echo [조치] ...
    pause        # ← uv 없을 때
    exit /b 127
)
...
if %EXIT_VAL% neq 0 (
    pause         # ← FAIL일 때
)
exit /b %EXIT_VAL%
```

의도 (issue-14/17/19 패턴과 동일): PASS면 pause 없이 종료 → 자동화 친화. FAIL/에러면 pause → 사용자 멈춤.

verify는 `grep -q -i "pause"`만 검사 → 비대칭 의도가 회귀 시 깨져도 미탐지. **PASS 시 pause 없음을 명시적으로 검증**해야 (`grep -c -i "pause" .bat` 후 첫 번째 pause만 ERRLEVEL≠0 분기에 있는지).

### P2-6 (3차): `docs/autoqafix-design.md` 갱신 누락

doctor가 새 진입점인데 디자인 문서에 언급 0건 (`grep doctor docs/` 0건). `cheatsheet.md:36`은 `autoqafix-doctor.sh`를 명시 — 좋음. CONTEXT.md 갱신 없음. 디자인 문서에 "진단 단계" 절을 짧게 추가 권장.

### P2-7 (3차): verify의 `out_ok` 변수가 TEST 5의 OK 분기 이후 TEST 8에서 재사용

```bash
# TEST 5: complete fixture (out_ok set)
...
# TEST 6: logs removed (out_fail set)
...
# TEST 7: --ping (mkdir -p logs to restore)
...
# TEST 8: default run doesn't ping (uses out_ok)
if echo "$out_ok" | grep -q "OK claudecli (";
```

TEST 7에서 `mkdir -p "$work/logs"`로 fixture 복원 → TEST 8 시점에 complete. 그러나 의존이 명시적이지 않아 향후 누군가가 TEST 7을 옮기면 깨질 수 있음.

수정안: TEST 8을 별도 `run_doctor "$work"` 호출로 분리하거나, `out_ok`의 유효 범위를 명시 코멘트로 표시.

### P2-8 (3차): `check_skills`가 `Path.home()`을 그대로 사용 — HOME 미설정 시 `/root`로 폴백

POSIX는 `HOME` 미설정이 정상이다 (`Path.home()`은 `/root` 또는 `pwd`로 폴백). doctor가 `/root/.claude/skills/tdd`를 검사하지만 실제 사용자의 skills는 `/home/me/.claude/skills/tdd`에 있을 수 있다. **doctor는 사용자가 명시적으로 호출하는 진입점**이라 `preflight`보다 더 엄격해야:

```python
home_str = os.environ.get("HOME")
if not home_str:
    d.fail("HOME", "$HOME 미설정", "export HOME=/path/to/home")
    return
home = Path(home_str)
```

(단, `core.preflight`도 같은 패턴이라 시정 범위는 별도 결정.)

## 직접 재현한 발견 (provenance)

| 발견 | 재현 스크립트 | 출력 일부 |
|---|---|---|
| P0-1 (pid 파싱 크래시) | (본 self-audit ad-hoc) | `ValueError: invalid literal for int() ... 'not_a_number'` + exit 0 |
| P0-2 (잠금이 디렉터리) | (본 self-audit ad-hoc) | `IsADirectoryError: [Errno 21] Is a directory: '.git/autoqafix.lock'` + exit 0 |
| P1-1 (다른 호스트 + 오래된 start) | (본 self-audit ad-hoc) | `FAIL 뮤텍스 잠금` (실제로는 reclaim 가능) |
| P1-4 / qwen P1-1 (deploy-to-staging 통과) | (본 self-audit ad-hoc) | `OK deploy 스크립트` |
| P2-3 / qwen T1-2 (빈 AUTOQAFIX_WRAPPERS 통과) | (본 self-audit ad-hoc) | `진단 완료: FAIL 0건` (warning 없음) |
| lock 빈 파일 → stale OK | (본 self-audit ad-hoc) | `OK 뮤텍스 잠금 없음 (stale lock — ...)` (정상 동작 확인) |
| lock garbage 라인 → stale OK | (본 self-audit ad-hoc) | 위와 동일 (정상 동작 확인) |
| 빈 pid (`pid=`) → stale OK | (본 self-audit ad-hoc) | 위와 동일 (정상 동작 확인) |

## 한계 자인

- **직전 리뷰 미선독 후 작성**: 본 self-audit은 **저장 후** `ls issue-20-review-result-*.md`로 1차 qwen 리뷰를 발견했다. 메모리([[issue-16-qwen-review-cycle]] 교훈 1) 위반. 결과적으로 qwen이 본 11건을 사후 통합하는 데 시간을 들였고, 만약 qwen 리뷰를 미리 읽었으면 본 self-audit은 1차 보강에 집중할 수 있었다.
- **재현 못 한 결론**: 없음. 모든 P0/P1은 위 표의 스크립트로 직접 재현.
- **환경 미검증**: Windows `.bat`, .ps1에서의 동작은 미검증 (CI가 WSL/Linux).
- **단독 self-audit의 한계**: issue-16의 4차 Fable 5 사례처럼 다른 렌즈의 리뷰어(보안, 성능, UX)가 본 self-audit의 빈틈을 잡을 가능성 있음. 본 self-audit은 **lock 검사 비정상 입력** 위주로 보강.

## 권장 우선순위

1. **P0-1 + P0-2 묶음 (1–2h)**: `core.peek_lock(path) -> dict | None` 추출 + `IsADirectoryError`/`ValueError` 처리 → doctor와 `core.acquire_lock` 양쪽에서 사용. **P0-1 fix는 기존 acquire_lock 버그까지 같이 해소** (issue-16 메모리의 "기존 버그 함께" 원칙).
2. **P1-1 / 3차 stale 정책 (30m)**: `core.is_lock_reclaimable(path) -> bool` 추출, doctor/autoqa/autofix 통일.
3. **P1-2 / 3차 lock 검증 0% 보강 (1h)**: verify-issue-20.sh에 잠금 시나리오 4개 추가 (정상 / same-host alive / same-host dead / cross-host stale / garbage / 디렉터리). P0-1·P0-2 회귀 잠금.
4. **P1-4 / qwen P1-1 deploy glob 좁히기 (10m)**: `repo.glob("deploy-to-env.*")` 또는 의도 코멘트.
5. **P2 전반 (별도 PR)**: 중첩 uv 최적화, 사설 API 정리, 빈 env WARN + fallback, run_pings 폴백 명시화, .bat pause 비대칭 회귀 잠금, 디자인 문서 갱신, verify TEST 8 분리.

## 부록 A: 합의/불일치 매트릭스

| 항목 | qwen 1차 | 본 self-audit 3차 | 처리 |
|---|---|---|---|
| P0-1 (pid 크래시) | ✅ 발견 | ✅ 재현·동의 | **P0 즉시** |
| P1-1 qwen (deploy-to-*) | "dead code" | "spec drift" | qwen/본 합의. 좁히기 |
| P1-2 qwen (tdd 중복) | "모호/중복" | **반대 — 스펙 명시 (issue-20.md:22)** | qwen 오판 |
| P1-3 qwen (env 미전파) | "누락" | **반대 — Popen 기본 상속** | qwen 오판 |
| P1-4 qwen (exit code 무시) | "false positive" | **반대 — 스펙 의도 (issue-9)** | qwen 오판 (단 stderr 노출은 minor 개선 권장) |
| P2-1 qwen (run_pings 폴백) | ✅ 발견 | ✅ 동의 | 명시화 |
| P2-2 qwen (commit msg 모호) | ✅ 발견 | cosmetic 동의 | commit amend |
| P2-3 qwen (fail_preformatted fragile) | 발견 | minor 동의 | 공용 API로 |
| T1-1 qwen (--ping FAKE_MODE) | 발견 | FAKE_MODE는 ping이 안 읽음 (검증됨) | 테스트 명료화만 |
| T1-2 qwen (빈 env) | 발견 | ✅ 재현·동의 | **P2-3 (즉시)** |
| T1-3 qwen (select-llm 부재) | 발견 | ✅ 동의 | verify 보강 |
| P0-2 (디렉터리 크래시) | ❌ **놓침** | ✅ 발견 | **P0 즉시** |
| P1-1 (3차 stale 정책) | ❌ **놓침** | ✅ 발견 | **P1 즉시** |
| P1-2 (3차 lock 검증 0%) | ❌ **놓침** | ✅ 발견 | **P1 즉시** |
| P1-3 (3차 wrapper 확장자 1/3) | ❌ **부분** (T1-1만) | ✅ 발견 | verify 보강 |
| P2-1 (3차 중첩 uv) | ❌ | ✅ 발견 | 별도 PR |
| P2-2 (3차 사설 API) | ❌ | ✅ 발견 | P0 묶음에 포함 |
| P2-5 (3차 .bat pause 비대칭) | ❌ | ✅ 발견 | verify 보강 |
| P2-6 (3차 design.md 갱신) | ❌ | ✅ 발견 | 별도 PR |
| P2-7 (3차 out_ok 재사용) | ❌ | ✅ 발견 | verify 보강 |
| P2-8 (3차 HOME 폴백) | ❌ | ✅ 발견 | 별도 결정 |

## 부록 B: 검증력 매트릭스

| 검사 항목 | spec | 구현 | verify 커버 | 재현 결과 |
|---|---|---|---|---|
| ① preflight(qa)·(fix) | OK / FAIL | OK / fail_preformatted | TEST 6 | OK |
| ② wrapper 존재 | OK / FAIL | OK / FAIL | TEST 5 (`.sh`만) | OK (.ps1/.bat 정상, verify 부족) |
| ③ usage JSON | OK / FAIL | OK / FAIL | ❌ happy path만 | OK |
| ④ select-llm | OK / FAIL | OK / FAIL | ❌ happy path만 | OK (디자인 의도, qwen과 불일치) |
| ⑤ deploy | OK / WARN | OK / WARN | TEST 4·5 | OK (P1-4 drift 있음) |
| ⑥ lock | OK / FAIL | OK / FAIL | **❌ 0개** | **P0-1·P0-2 크래시** |
| ⑦ skills (4종) | OK / FAIL | OK / FAIL | ❌ OK 라인 존재만 | OK |
| --ping | 크레딧 경고 + 실행 | OK | TEST 7 | OK |
| exit = FAIL 수 | spec | OK | TEST 4·6 | OK |
| 비정상 잠금 → FAIL | (spec 외) | ❌ crash | ❌ | **P0** |
| 빈 AUTOQAFIX_WRAPPERS | (spec 외) | ❌ silent | ❌ | **P2-3** |

표면 15/15 + 17/17 = "구현 완료"로 단정하기엔 ⑥번 검증이 완전히 비어 있고, 그 빈틈에 P0가 살고 있다.
