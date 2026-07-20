# Issue-20: autoqafix-doctor — 코드 품질 감사 결과

> **감사 일시**: 2026-07-11 (commit `029ce344`)
> **감사 범위**: `autoqafix-doctor.py`, `autoqafix-doctor.{sh,ps1,bat}`, `verify-issue-20.sh`, 및 연관 모듈(`autoqafix_core.py`, `autofix.py`)
> **사후 변경**: doctor 관련 파일들에 대한 후속 커밋 없음 (`git log 029ce34..HEAD -- .claude/skills/autoqafix/autoqafix-doctor.py` 빈 결과, 동일 파일들 HEAD와 동일)

---

## 1. 중복 검사: `check_preflight("fix")`와 `check_skills()`가 동일 결함을 이중 보고한다

**심각도**: 중간 (사용자 혼란, BUT 로직 오류는 아님)

`check_preflight`가 `core.preflight("fix", repo)`를 호출하면 내부 검사 ⑦에서 `~/.claude/skills/{autotdd,tdd2,aacpd}` 존재를 확인한다. 이후 `check_skills()`도 `~/.claude/skills/{autotdd,tdd2,aacpd,tdd}`를 확인한다. 따라서 `autotdd`/`tdd2`/`aacpd` 중 하나라도 없으면 **2건의 FAIL**이 출력된다:

```
FAIL preflight(fix)
[원인] ~/.claude/skills/autotdd 없음
[조치] autotdd 설치 확인
FAIL 스킬 autotdd
[원인] ~/.claude/skills/autotdd 없음
[조치] autotdd 설치 확인
```

이는 issue-20.md의 요구사항 ⑦(`~/.claude/skills/{autotdd,tdd2,aacpd,tdd}`)과 preflight의 내부 검사 ⑦이 의도치 않게 겹친 결과다. 설계 문서에는 "preflight 상위 집합"이라고만 정의되어 있어 이 중복이 명시적이지 않다.

### 권장 조치

두 가지 접근 중 하나:

- **A)** `check_skills()`에서 `autotdd`/`tdd2`/`aacpd`를 제외하고 `tdd`만 검사한다 — preflight가 이미 검사한 것은 다시 검사하지 않는다는 원칙.
- **B)** `check_preflight("fix")`가 실패했을 때, 그 하위 항목 ⑦의 실패 메시지를 기억해두었다가 `check_skills()`에서 같은 결함을 건너뛴다.

A가 단순하다.

---

## 2. `deploy-to-*` glob 패턴이 테스트되지 않았다

**심각도**: 낮음 (기능은 구현됨, 단 미검증)

`check_deploy()` 함수 내부:

```python
found = any((repo / f"deploy{e}").is_file() for e in exts) or any(
    p.is_file() for e in exts for p in repo.glob(f"deploy-to-*{e}")
)
```

`deploy-to-*{ext}` glob 패턴은 요구사항에 포함되어 있고(`deploy-to-env.{sh,ps1,bat}`) 코드도 정확하지만, `verify-issue-20.sh`는 `deploy.sh`만 생성하고 검증한다. `deploy-to-prod.sh`나 `deploy-to-staging.ps1` 등이 올바르게 감지되는지는 미검증 상태로 남았다.

참고: 구현 결과 항목에서 "구현 중 잡은 버그"로 `any(glob 제너레이터)` 평가 문제는 수정되었다고 기록되어 있으나, 그 수정 후에도 이 패턴이 테스트되지 않았다.

---

## 3. `select-llm "none"` 분기 미테스트

**심각도**: 낮음 (기능 분기 중 하나만 테스트됨)

`verify-issue-20.sh`는 항상 `AUTOQAFIX_WRAPPER=claudecli` 환경변수를 설정하여 `select-llm.py`가 우회적으로 `"claudecli"`를 반환하도록 만든다. 따라서 `select-llm`이 `"none"`을 출력하는 경우(사용 가능한 LLM이 하나도 없을 때)의 코드 경로는 테스트되지 않았다.

`check_select_llm()`에서 이 분기의 로직:

```python
if not timed_out and (selected in names or selected == "none"):
    d.ok(f"select-llm ({selected})")
```

`"none"`이 names에 포함되어 있지 않더라도 통과하도록 설계되어 있다. 문법적으로는 올바르지만, 이 경로가 실제로 동작하는지 확인된 바 없다.

---

## 4. `check_usage_scripts`의 60초 타임아웃이 환경에 따라 빡빡할 수 있다

**심각도**: 낮음 (에지 케이스)

`check_usage_scripts()`는 각 usage 스크립트에 60초의 타임아웃을 준다:

```python
rc, out, _, timed_out = core.run_with_timeout(
    ["uv", "-q", "run", str(script)], 60,
)
```

`uv -q run`은 첫 실행 시 PEP-723 스크립트의 의존성을 resolving + installing 해야 하므로, 캐시가 비어 있는 환경(Cold boot, CI 첫 실행)에서는 60초가 부족할 수 있다. 특히 `usage-claudecli.py`는 `~/.claude/.credentials.json`과 `~/.cache/claude/usage.json`을 읽고, 캐시 미스 시 외부 API(`claude.ai/api/oauth/usage`)를 호출한다 — 여기에 `uv` resolving 시간까지 합쳐지면 지연이 누적된다.

나머지 usage 스크립트(`usage-minimaxcli.py`, `usage-qwencli.py`)도 각각 외부 API를 호출할 수 있다.

---

## 5. `.ps1` 런처에 에러 시 `pause` 누락 (`.bat`과 불일치)

**심각도**: 낮음 (사용자 경험 일관성)

`autoqafix-doctor.bat`은 `%EXIT_VAL% neq 0`일 때 `pause`를 호출하여 에러 메시지를 사용자가 읽을 시간을 준다:

```bat
if %EXIT_VAL% neq 0 (
    pause
)
```

`autoqafix-doctor.ps1`은 이에 상응하는 처리가 없다. PowerShell 런처에서 doctor가 실패하면 콘솔 창이 즉시 닫혀 사용자가 오류 메시지를 읽지 못할 수 있다.

---

## 6. `check_wrappers`와 `run_pings`의 폴백 정책 불일치

**심각도**: 낮음 (설계 일관성)

`check_wrappers()`는 오직 `wrapper_dir` (env `AUTOQAFIX_WRAPPER_DIR` 또는 `WRAPPER_DEFAULT_DIR`)만 확인한다 — PATH 폴백은 있지만 스킬 기본 디렉토리로의 폴백은 없다.

반면 `run_pings()`는 먼저 `wrapper_dir`에서 ping 스크립트를 찾고, 없으면 `WRAPPER_DEFAULT_DIR`로 폴백한다:

```python
ping = wrapper_dir / f"ping-{name}.sh"
if not ping.is_file():
    ping = WRAPPER_DEFAULT_DIR / f"ping-{name}.sh"
```

래퍼 검사와 ping 검사가 같은 디렉토리 결정 규칙을 따라야 일관성이 있다. `ping`이 `wrapper_dir` + `WRAPPER_DEFAULT_DIR` 이중 경로를 탐색한다면, wrapper 검사도 동일한 이중 경로를 탐색하거나, 반대로 ping 검사도 단일 경로로 고정해야 한다.

---

## 7. `autofix` 모듈 간접 의존: doctor가 `autofix`에서 `parse_wrapper_spec`만 빌려온다

**심각도**: 낮음 (모듈 결합도)

`autoqafix-doctor.py`는 다음 import를 한다:

```python
import autofix
```

이 모듈은 300라인에 달하는 `autofix` 엔진 전체(`ensure_worktree`, `enumerate_items`, `dispatch`, `select_llm`, `stamp_tier`, `rename_to_manual` 등)를 포함한다. doctor는 이 중 `parse_wrapper_spec()` 하나만 사용한다.

이는 진단 도구(doctor)가 실행 엔진(autofix) 전체를 전이 의존하게 만든다 — 만약 `autofix.py`가 미래에 `autoqafix-doctor.py`와 호환되지 않는 방식으로 변경되거나, 무거운 초기화 로직을 추가하면 doctor도 영향을 받는다.

### 권장 조치

`parse_wrapper_spec()`을 `autoqafix_core.py`로 이동하거나, doctor 내부에 동등한 작은 파서를 인라인한다.

---

## 8. `check_preflight`의 role 단위 OK/FAIL 계수 방식이 예상과 다를 수 있다

**심각도**: 정보성 (설계 결정이지만 문서화 미흡)

`check_preflight()`는 role당 하나의 출력 단위로 처리한다:

- 모든 preflight 항목 통과 → `OK preflight(qa)`, `OK preflight(fix)`
- 1건이라도 실패 → 실패 메시지 1건당 `FAIL preflight(qa)` 1줄씩

이로 인해 exit code가 preflight 내부의 세부 실패 건수까지 반영한다:
- `logs/`가 없고(1건) + git user.email 미설정(1건) → `FAIL preflight(qa)` 2줄 → exit 2

이는 "항목별 OK/FAIL"이라는 issue-20 요구사항과 일관되지만, 사용자 입장에서는 `FAIL preflight(qa)`가 preflight 자체의 하나의 항목인지, preflight 내부의 개별 검사들인지 구분하기 어렵다. 구현 결과 노트에는 이 판단이 기록되어 있지만, 출력 포맷 명세에 명시적으로 적혀 있지 않다.

---

## 9. Doctor가 래퍼 실행 파일의 `+x` 퍼미션을 확인하지 않는다

**심각도**: 낮음 (에지 케이스)

`check_wrappers()`는 `.sh`/`.ps1`/`.bat` 파일의 존재만 `is_file()`으로 확인하고, 실행 권한(`os.access(x, os.X_OK)`)은 확인하지 않는다. `.sh` 파일이 존재하지만 실행 비트가 없으면 `run_pings()`에서 `bash`로 직접 실행하므로 문제가 없고, `.bat`/`.ps1`도 각각 `cmd`/`powershell`이 실행한다. 그러나 Unix에서 `shutil.which()`로 PATH에서 찾은 항목은 자연스럽게 실행 가능하지만, `wrapper_dir`에 있는 `.sh`가 실행 불가능이어도 OK로 보고된다.

---

## 10. `check_deploy`에서 `deploy-to-*` 패턴이 `deploy-to-env`만 지원하는지 `deploy-to-anything`을 지원하는지 명세와 코드 간 차이

**심각도**: 정보성

issue-20.md 요구사항 ⑤에는 `deploy-to-env.{sh,ps1,bat}`라고 특정 이름이 명시되어 있다. 그러나 코드는 `deploy-to-*{ext}` glob을 사용한다:

```python
repo.glob(f"deploy-to-*{e}")
```

이는 `deploy-to-env.sh` 뿐 아니라 `deploy-to-production.sh`, `deploy-to-staging.sh` 등 모든 `deploy-to-*` 패턴을 허용한다. 명세보다 관대한 구현이며, 긍정적인 확장(유연성 향상)이다. 그러나 검증 테스트에서 `deploy-to-env.sh` 외의 다른 패턴이 생성되지 않아 이 차이가 눈에 띄지 않는다.

---

## 요약

| # | 항목 | 심각도 | 분류 |
|---|------|--------|------|
| 1 | `check_preflight("fix")`와 `check_skills()`의 중복 검사 → 동일 결함 이중 FAIL | 중간 | 새로 도입된 미비점 |
| 2 | `deploy-to-*` glob 패턴 미테스트 | 낮음 | 안일함 |
| 3 | `select-llm "none"` 분기 미테스트 | 낮음 | 안일함 |
| 4 | usage 스크립트 60초 타임아웃이 콜드 환경에서 빡빡할 수 있음 | 낮음 | 안일함 |
| 5 | `.ps1` 런처에 에러 시 `pause` 누락 (`.bat`과 불일치) | 낮음 | 안일함 |
| 6 | `check_wrappers`와 `run_pings`의 디렉토리 폴백 정책 불일치 | 낮음 | 설계 일관성 |
| 7 | `autofix` 모듈 전체를 `parse_wrapper_spec` 하나 때문에 import | 낮음 | 모듈 결합도 |
| 8 | preflight role 단위 계수 방식의 문서화 부족 | 정보성 | 문서화 |
| 9 | 래퍼 실행 파일의 `+x` 퍼미션 미확인 | 낮음 | 안일함 |
| 10 | 명세(`deploy-to-env`)와 코드(`deploy-to-*`) 간 차이 | 정보성 | 긍정적 확장 |

### 1건의 P1급 발견

**#1 중복 검사**는 실제 운영에서 사용자가 동일한 문제에 대해 2배의 FAIL을 보고 받게 만든다. 스킬이 없을 때 exit code가 실제보다 높게 나와 혼란을 준다. 가장 먼저 수정할 가치가 있다.

### 3건의 P3급 안일함

**#2, #3**은 테스트 커버리지 누락. **#5**는 크로스-플랫폼 사용자 경험 불일치. 모두 고치기 쉬우며 회귀 위험도 낮다.
