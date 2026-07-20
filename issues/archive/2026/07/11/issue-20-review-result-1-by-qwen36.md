# issue-20 Code Quality Audit — Review Result #1

**Date:** 2026-07-11
**Commit:** 029ce34 issue-20: autoqafix-doctor — 사전 점검 도구
**Audited files:** 6 files, 458 insertions

---

## 1. Launcher scripts (sh/bat/ps1) — ✅ Convention compliant

- `autoqafix-doctor.sh`, `.bat`, `.ps1` 모두 기존 6개 런처 패밀리(autoqa/autofix/autodev + loop 3종)와 패턴 일치
- uv detection → `[원인]`/`[조치]` → SCRIPT_DIR → `uv -q run` → exit code 전파, 모든 플랫폼에서 동일
- `.bat`의 `pause` 포함/`.ps1`의 생략 등 플랫폼별 관례도 정확히 따름
- **결론: 별도 이슈 없음**

---

## 2. autoqafix-doctor.py — P0 (Fix Required)

### P0-1: `check_lock` — `int(info.get("pid") or "0")` 의 silent type coercion

```python
pid_dead = same_host and not core._pid_alive(int(info.get("pid") or "0"))
```

`_read_lock`은 key=value 파서이므로 `info["pid"]`는 **string**. 만약 lock 파일에 `pid=abc` 같은 더미 값이 있으면 `int("abc")`가 `ValueError`를 던진다. `or "0"`는 `None`만 catch하고 빈 문자열 `""`는 `int("")`로 이어져 역시 `ValueError`.

**권장:** `int(info.get("pid") or "0")` → `int(info.get("pid") or 0)` 또는 try/except 처리.

---

## 3. autoqafix-doctor.py — P1 (Should Fix)

### P1-1: `check_deploy` — 존재하지 않는 glob 패턴 `deploy-to-*`

```python
found = any((repo / f"deploy{e}").is_file() for e in exts) or any(
    p.is_file() for e in exts for p in repo.glob(f"deploy-to-*{e}")
)
```

프로젝트의 실제 deploy 스크립트는 `deploy.sh` / `deploy-to-<env>.sh` (예: `deploy-to-dev.sh`) 형식이다. `deploy-to-*` glob은 환경 이름이 없는 임의 파일을 찾는데, 이런 파일은 코드베이스에 존재하지 않는다. 이 glob은 **dead code**이면서 동시에 **오해의 소지가 있는 로직**.

**권장:** `deploy-to-*` glob 제거 또는 `deploy-to-[a-z]*` 등으로 명확히.

### P1-2: `check_skills` — `REQUIRED_SKILLS = ("autotdd", "tdd2", "aacpd", "tdd")` 의 `tdd` 중복

`check_preflight(role="fix")`도 이미 `autotdd, tdd2, aacpd`를 검증한다. `tdd` 스킬은 preflight에 포함되지 않지만 doctor는 필수로 체크한다. 이는 **의도된 확장인지 명확하지 않음**.

**권장:** `REQUIRED_SKILLS`에 주석 추가 ("tdd는 issue-XX에서 추가됨") 또는 preflight에 통합.

### P1-3: `check_usage_scripts` — 환경 변수 전파 누락

```python
rc, out, _, timed_out = core.run_with_timeout(
    ["uv", "-q", "run", str(script)], 60,
)
```

`AUTOQAFIX_WRAPPER` 등 환경 변수가 서브프로세스로 전달되지 않는다. `run_with_timeout`은 `env=None` 시 부모의 env를 상속하지만, 테스트 픽스처에서 `AUTOQAFIX_WRAPPER`를 설정해도 usage 스크립트에 전달되지 않을 수 있다.

**권장:** `env=os.environ.copy()` 명시적 전달 또는 문서화.

### P1-4: `check_select_llm` — exit code 무시

```python
_, out, _, timed_out = core.run_with_timeout(
    ["uv", "-q", "run", str(script)], 120,
)
selected = out.strip()
if not timed_out and (selected in names or selected == "none"):
```

`select-llm.py`가 exit 1 (오류)로 종료했지만 stdout에 우연히 wrapper name이 있으면 `OK`로 판정된다. exit code 1은 "선택 실패"를 의미하므로 이는 **false positive**.

**권장:** exit code도 함께 검사 (`rc == 0 or rc == 2`).

---

## 4. autoqafix-doctor.py — P2 (Nice to Fix)

### P2-1: `run_pings` — `WRAPPER_DEFAULT_DIR` 폴백이 `AUTOQAFIX_WRAPPER_DIR`를 무시

```python
ping = wrapper_dir / f"ping-{name}.sh"
if not ping.is_file():
    ping = WRAPPER_DEFAULT_DIR / f"ping-{name}.sh"  # ← hardcoded fallback
```

`AUTOQAFIX_WRAPPER_DIR`를 설정한 사용자가 ping 스크립트도 그 디렉토리에 두고 싶다면 이 폴백은 의도하지 않은 경로를 찾는다.

**권장:** 폴백도 `AUTOQAFIX_WRAPPER_DIR` 기반이거나, 명시적 경고 출력.

### P2-2: `check_wrappers` — `any(generator)` 의 성능 (theoretical)

```python
in_dir = any(
    (wrapper_dir / f"{name}{ext}").is_file() for ext in (".sh", ".ps1", ".bat")
)
```

issue-20 commit message에서 본인이 "any(glob 제너레이터)가 내용이 아닌 제너터 객체를 평가해 deploy 부재를 OK로 오판 → 수정"이라고 적었으나, 현재 코드는 이미 수정된 상태(제너터가 아니라 generator expression + `is_file()` 평가). Python 3에서는 `any()`가 lazy하게 동작하므로 **이미 올바르게 동작 중**. 다만 issue 기록이 남아있어 혼란스러울 수 있음.

**권장:** commit message에 "fixed" 명시 또는 코드에 주석 추가.

### P2-3: `Doctor` 클래스 — `fail_preformatted`의 fragile 의존

```python
def fail_preformatted(self, item: str, msg: str) -> None:
    """preflight()가 이미 만든 [원인]/[조치] 2줄 메시지를 그대로 사용."""
    self.fails += 1
    print(f"FAIL {item}")
    print(msg)
```

`preflight()`가 반환하는 메시지 포맷(`[원인]...\n[조치]...`)이 바뀌면 `fail_preformatted`이 깨진다. public API가 아닌 `_msg()` 내부 함수에 의존.

**권장:** `preflight()`가 `(success: bool, messages: list[str])` tuple을 반환하거나, doctor가 메시지를 직접 파싱하지 않고 실패 여부만 받도록.

---

## 5. verify-issue-20.sh — P1 (Test Gaps)

### T1-1: `--ping` 테스트가 `PING_WRAPPER` 전파에 의존하지만 불명확

```bash
out_ping="$(PING_WRAPPER="$LIB/fake-wrapper.sh" FAKE_MODE=ok run_doctor "$work" --ping)"
```

`run_doctor`는 `(cd "$dir" && bash ...)` 서브쉘로 실행되므로 `PING_WRAPPER`는 전파된다. 그러나 `FAKE_MODE`도 전파되는지 명시적 검증이 없음. ping-*.sh 스크립트가 `FAKE_MODE`를 읽는지 확인 필요.

### T1-2: `AUTOQAFIX_WRAPPERS=""` (빈 문자열) 테스트 누락

빈 문자열일 때 `parse_wrapper_spec("")`가 `{}`를 반환하면 아무 체크도 안 하는데, 이 시나리오가 테스트되지 않음.

### T1-3: `select-llm.py` 파일이 없을 때 테스트 누락

`SCRIPT_DIR / "select-llm.py"`가 없어도 에러 없이 `OK`로 넘어갈 수 있는지 검증 필요.

---

## 6. Static Analysis — ✅ Pass

- `ruff check`: clean (no warnings)
- `py_compile`: syntax OK
- `bash -n autoqafix-doctor.sh`: pass
- `.bat`의 `pause` 포함: pass

---

## 7. Summary Table

| ID    | Severity | File                        | Description                        |
|-------|----------|-----------------------------|------------------------------------|
| P0-1  | P0       | autoqafix-doctor.py         | `int(pid)` silent coercion         |
| P1-1  | P1       | autoqafix-doctor.py         | dead code: `deploy-to-*` glob      |
| P1-2  | P1       | autoqafix-doctor.py         | `REQUIRED_SKILLS` tdd 중복/미해석  |
| P1-3  | P1       | autoqafix-doctor.py         | env var 전파 누락 (usage scripts)  |
| P1-4  | P1       | autoqafix-doctor.py         | select-llm exit code 무시          |
| P2-1  | P2       | autoqafix-doctor.py         | run_pings hardcoded 폴백           |
| P2-2  | P2       | autoqafix-doctor.py         | commit message의 "fixed" 모호       |
| P2-3  | P2       | autoqafix-doctor.py         | fail_preformatted fragile 의존      |
| T1-1  | P1       | verify-issue-20.sh          | --ping 테스트 FAKE_MODE 전파 불명   |
| T1-2  | P1       | verify-issue-20.sh          | 빈 AUTOQAFIX_WRAPPERS 테스트 누락  |
| T1-3  | P1       | verify-issue-20.sh          | select-llm.py 부재 테스트 누락     |

---

## 8. Overall Assessment

**구현 품질: 양호.** launcher scripts는 프로젝트 컨벤션을 완벽히 따르고, doctor.py의 핵심 로직(7개 진단 체크)은 명확하고 잘 구조화됨. ruff/pyright clean.

**주요 우려:**
1. **P0-1**이 유일한 즉시 수정 항목. lock 파일의 `pid` 값이 비정상적일 때 crash 가능
2. **P1-4** (select-llm exit code 무시)는 false positive를 유발할 수 있는 실용적 문제
3. **verify-issue-20.sh**의 테스트 커버리지가 functional path는 잘 덮지만 edge case (빈 spec, 누락 파일)가 부족

**안일함 발견:**
- `deploy-to-*` glob (P1-1): 코드베이스에 존재하지 않는 패턴을 체크하는 dead code를 그대로 둠. "일단 돌아가면 됨" 접근
- `REQUIRED_SKILLS`에 `tdd` 추가 (P1-2): preflight와 doctor의 필수 스킬 목록이 분리되어 있지만 아무도 일관성을 관리하지 않음
- `run_pings`의 hardcoded 폴백 (P2-1): `AUTOQAFIX_WRAPPER_DIR` 설정의 의도를 완전히 무시하는 폴백 경로를 그대로 둠
