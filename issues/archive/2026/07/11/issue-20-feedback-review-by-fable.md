# issue-20 리뷰 피드백 종합 판정 (by Fable 5)

- **판정 일시**: 2026-07-11
- **대상**: `issue-20-review-result-{1..4}-by-{qwen36,gemini35,minimax3,deepseek4}.md`
- **판정 기준 커밋**: `029ce34` (issue-20: autoqafix-doctor)
- **판정 방법**: 4개 리뷰의 전 지적사항을 실제 코드(`autoqafix-doctor.py`, `autoqafix_core.py`, `select-llm.py`, `verify-issue-20.sh`, 런처 3종, `wrappers/`, `autofix.py`, `usage-*.py`)와 스펙(`issues/archive/2026/07/11/issue-20.md`)에 대조하여 must-fix(실수 인정) / good-to-fix(개선 수용) / reject(반박)로 분류

---

## 0. 총괄 (두괄식 요약)

- **총 지적사항 41건** (판정 대상 40건 + minimax 자진 철회 1건)
- **분류 결과**: must-fix **10건** / good-to-fix **19건** / reject **11건** → **전체 수용률 72.5%** (29/40)
- **최종 수정 계획: 14개 항목** (must-fix 계열 M1~M6 6개 + good-to-fix 계열 G1~G8 8개)이 **수용 지적 29건 전부를 커버** (커버율 100%, 항목당 평균 2.07건)
- **보고서별 유효성**: minimax3 92% > gemini35 83% > deepseek4 70% > qwen36 45%
- **최중요 결론**: 크래시성 P0 2건(pid 파싱·디렉터리 잠금)과 그 회귀를 못 잡는 **lock 검증 0% 커버리지**가 여전히 미해결 — M1~M3이 최우선

### 보고서별 집계

| 보고서 | 총 지적 | must-fix | good-to-fix | reject | 철회 | 수용률 | 유효성 평가 |
|---|---|---|---|---|---|---|---|
| 1차 qwen36 | 11 | 2 | 3 | 6 | – | **45%** | 유일하게 P0-1을 최초 발견했으나 오판 6건으로 정밀도 최하. 코드 실측 없이 추정한 항목(P1-2/P1-3/P1-4)이 모두 기각됨 |
| 2차 gemini35 | 6 | 3 | 2 | 1 | – | **83%** | 소수 정예. 다른 리뷰가 못 본 must-fix 3건(run_pings Windows 크래시, stale 정책 drift, Windows 런처 오안내)을 발굴 — **must-fix 발굴 밀도 1위** |
| 3차 minimax3 | 13 | 5 | 7 | 1 | 1 | **92%** | 전 항목 직접 재현 기반이라 정확도 1위. P0-2·lock 검증 0% 등 핵심 보강 + qwen 오판 3건 판별도 정확. 유일 기각은 P2-8(HOME) 전제 오류 |
| 4차 deepseek4 | 10 | 0 | 7 | 3 | – | **70%** | must-fix 발굴 0건으로 심각도 발굴력은 낮으나 테스트 갭·결합도 지적이 견실. deploy glob을 "긍정적 확장"으로 본 유일한 리뷰(본 판정과 일치) |
| **합계** | **40** | **10** | **19** | **11** | **1** | **72.5%** | |

---

## 1. must-fix — 실수 인정 (10건)

| # | 출처 | 지적 | 인정 근거 (실측) |
|---|---|---|---|
| MF-1 | qwen P0-1, minimax P0-1 | `check_lock`의 `int(info.get("pid") or "0")` — 비정상 pid에서 `ValueError` 크래시 | minimax 재현 확인. traceback 후 **exit 0으로 정상 종료 가장** — 진단 도구로서 최악의 실패 양식. `acquire_lock`(autoqafix_core.py:142)에도 같은 패턴 잠복 |
| MF-2 | minimax P0-2 | 잠금이 디렉터리면 `_read_lock`의 `read_text()`가 `IsADirectoryError` 크래시 | minimax 재현 확인. MF-1과 동일 경로(`_read_lock` OSError 미처리), 동일하게 exit 0 가장 |
| MF-3 | gemini ④, minimax P1-1(3차) | `check_lock`이 `AUTOQAFIX_LOCK_STALE_SEC`(4h) 기반 `is_stale` 판정을 무시 → 회수 가능한 락을 FAIL로 오진, "락 삭제" 유도 | `acquire_lock`(core:140–154)은 `pid_dead or is_stale` 이중 조건, doctor(doctor.py:150)는 `pid_dead`만. 2개 리뷰 독립 발견 + minimax 재현 |
| MF-4 | minimax P1-2(3차) | `verify-issue-20.sh`의 lock 검증 **0% 커버리지** — 잠금 파일을 만드는 테스트가 1개도 없어 MF-1·MF-2 회귀가 자동 미탐지 | verify 실측: 8개 시나리오 중 `check_lock` 관련 0개. "15/15 PASS"가 빈 검사를 가장 — issue-16 교훈("verify PASSED여도 검증력 빈 검사 주의")과 동일 함정 |
| MF-5 | qwen T1-2, minimax P2-3(3차) | 빈 `AUTOQAFIX_WRAPPERS`(`""`)면 wrapper/usage 검사가 통째로 무실행인데 **경고 없이 FAIL 0 통과** | minimax 재현 확인. `os.environ.get(..., DEFAULT)`는 빈 문자열을 default로 폴백하지 않음. 진단 도구가 오설정 자체를 침묵 통과시키는 것은 명백한 실수 |
| MF-6 | gemini ③ | `run_pings`가 `["bash", str(ping)]` 하드코딩 + `ping-*.sh`만 탐색 — 네이티브 Windows에서 `--ping` 시 `FileNotFoundError` 크래시 | `wrappers/`에 `ping-*.bat`·`ping-*.ps1`이 **전 래퍼에 실존**하는데 미사용. `.bat`/`.ps1` 런처를 제공하는 도구가 내부에서 Windows를 못 돌게 만든 실수 |
| MF-7 | gemini ⑥ | `.bat`/`.ps1` 런처의 uv 부재 조치 안내가 Linux 전용 `curl -LsSf …/install.sh \| sh` | autoqafix-doctor.bat:5, .ps1:3 실측 확인. Windows 콘솔에서 그대로 실행하면 실패하는 잘못된 사용자 안내. (기존 9종 런처 전체에서 물려받은 패턴 — 시정 범위는 12종 전체) |

> MF-1·MF-2는 발견 2건이 수정 1건으로 합쳐지고(동일 `_read_lock` 경로), MF-3~MF-7은 각 1건씩. 표의 행은 "결함 단위" 7행이지만 원본 지적 단위로는 10건(qwen 2 + gemini 3 + minimax 5)이다.

## 2. good-to-fix — 개선 수용 (19건)

| # | 출처 | 지적 | 수용 사유 |
|---|---|---|---|
| GF-1 | gemini ①, deepseek #1 | `check_preflight("fix")`와 `check_skills()`가 autotdd/tdd2/acpd 부재를 **이중 FAIL 계수** → exit code 부풀림 | 사실 확인. 단 스펙(①+⑦)이 둘 다 요구한 구조적 결과라 "실수"보다는 dedupe 개선으로 수용 |
| GF-2 | gemini ②, minimax P2-1(3차) | usage 스크립트 중복 실행 — doctor가 직접 1회 + select-llm 내부(fetch_usage) 1회, 총 `uv` 직렬 8회 | select-llm.py:57–79 실측 확인. 성능 개선으로 수용 (기본 3래퍼 기준 콜드 수 초) |
| GF-3 | deepseek #7 | `parse_wrapper_spec` 하나 때문에 `import autofix`(실행 엔진 전체) 전이 의존 | 타당. `autoqafix_core`로 이동이 정석 |
| GF-4 | minimax P1-4(부분), deepseek #2, deepseek #10 | deploy glob(`deploy-to-*`)의 의도 명시 부재 + `deploy-to-<env>.sh` 감지 미테스트 | 코드는 옳다(아래 RJ-1 참조)는 것이 본 판정이나, 4개 리뷰 중 3개가 서로 다르게 오독한 것 자체가 주석 부재의 증거. 의도 주석 + verify 케이스 추가 수용. minimax의 "좁히기" 대안은 기각, "주석 명시" 대안만 수용 |
| GF-5 | deepseek #3 | `select-llm "none"` 분기 미테스트 | 테스트 갭 사실. verify 보강 수용 |
| GF-6 | qwen T1-3 | `select-llm.py` 부재 시나리오 미테스트 | 부재 시 FAIL로 동작함은 확인(빈 출력 → 판정식 불통과)되나 회귀 잠금 없음. verify 보강 수용 |
| GF-7 | minimax P1-3(3차) | `check_wrappers` 3종 확장자 중 verify가 `.sh`만 검증 (1/3) | 테스트 갭 사실. `.ps1` 단독 래퍼 케이스 추가 수용 |
| GF-8 | minimax P2-5(3차) | `.bat` pause 비대칭(PASS 시 무-pause) 의도를 verify가 `grep -q pause`로만 검사 | 회귀 잠금 부재 사실. 수용 |
| GF-9 | minimax P2-7(3차) | verify TEST 8이 TEST 5의 `out_ok`를 암묵 재사용 — 의존이 비명시적 | 현재는 정상이나 재배치에 취약. 범위 주석 수용 |
| GF-10 | qwen P2-1, deepseek #6 | `run_pings`의 `WRAPPER_DEFAULT_DIR` 폴백 — `check_wrappers`(dir∨PATH)와 정책 비대칭 | 폴백 자체는 구현 결과 ②에 문서화된 의도이고 사용자 dir이 우선 탐색되므로 qwen의 해악 시나리오는 성립 안 하나, 코드 내 의도 주석·정책 정렬은 수용 |
| GF-11 | qwen P2-3 | `fail_preformatted`가 `core._msg`의 `[원인]\n[조치]` 포맷에 암묵 의존 | 결합 사실. preflight 반환 계약 공식화(또는 구조화 반환) 수용 |
| GF-12 | minimax P2-2(3차) | `core._lock_path`/`_read_lock` 사설 API를 doctor/autoqa/autofix 3곳이 직접 호출 | 사실. MF-1 수정(public `peek_lock` 추출)과 자연 결합 |
| GF-13 | minimax P2-6(3차) | `docs/autoqafix-design.md`에 doctor 언급 0건 | 사실(cheatsheet만 갱신됨). 진단 절 추가 수용 |
| GF-14 | deepseek #8 | preflight role 단위 FAIL 계수 방식이 출력 포맷 명세에 미기재 | 구현 결과에는 기록됨. 모듈 docstring 한 줄 보강으로 수용 |

> 원본 지적 단위 19건(qwen 3 + gemini 2 + minimax 7 + deepseek 7)이 개선 항목 14행으로 묶임.

## 3. reject — 반박 (11건)

| # | 출처 | 지적 | 반박 근거 (실측) |
|---|---|---|---|
| RJ-1 | qwen P1-1 | `deploy-to-*` glob은 "존재하지 않는 파일을 찾는 dead code" | **오판.** glob의 대상은 이 codebase가 아니라 **진단 대상 repo**다. 스펙(issue-20.md:18)의 `deploy-to-env.{sh,ps1,bat}`에서 "env"는 환경명 플레이스홀더(qwen 스스로 "실제 형식은 `deploy-to-<env>.sh`"라 인용하며 자가당착). 넓은 glob이 스펙 의도에 부합 |
| RJ-2 | qwen P1-2 | `REQUIRED_SKILLS`의 `tdd` 추가가 "의도 불명확한 중복" | **오판.** issue-20.md:22 스펙 ⑦이 `{autotdd,tdd2,acpd,tdd}` 4종을 명시. preflight 3종은 issue-10의 좁은 정의이고 doctor의 4종은 스펙 그대로 |
| RJ-3 | qwen P1-3 | usage 서브프로세스에 "환경 변수 전파 누락" | **오판.** `subprocess.Popen`은 `env=None`(기본)일 때 부모 env를 상속. verify가 `PING_WRAPPER`를 상속만으로 전달하는 것이 실증 |
| RJ-4 | qwen P1-4 | select-llm "exit code 무시는 false positive" | **오판.** exit 2는 "none" 정상 경로(issue-9 디자인, select-llm.py:161 명시)이고 출력 판정은 doctor.py:118 주석에 기록된 의도. exit 1류 오류는 stderr `[경고]`(select-llm.py:60–77)로 이미 노출 |
| RJ-5 | qwen P2-2 | 커밋 메시지/이슈 기록의 `any(glob제너레이터)` 버그 언급이 혼란 | 구현 결과 기록이 이미 "…오판 **→ 수정**"으로 종결을 명시(issue-20.md:50–51). 커밋은 push 완료라 amend 불가. 코드도 정상 동작 |
| RJ-6 | qwen T1-1 | `--ping` 테스트의 `FAKE_MODE` 전파 불명확 | 전파는 표준 env 상속으로 정상 동작(RJ-3과 동일 원리). 더욱이 `FAKE_MODE=ok`는 fake-wrapper.sh:49의 기본값과 동일해 전파 여부와 무관하게 결과 불변 |
| RJ-7 | gemini ⑤ | deploy 스크립트의 `+x` 실행 권한 미검사 | 스펙 ⑤는 존재 확인만 요구하며 부재조차 FAIL 아닌 WARN(대상 repo 소관 원칙). 스위트 관례는 `bash script.sh` 직접 실행이라 +x 무관, Windows `.bat`/`.ps1`엔 +x 개념 자체가 없음 |
| RJ-8 | deepseek #4 | usage 60초 타임아웃이 콜드 환경에서 부족 가능 | usage 스크립트 3종 모두 PEP-723 `dependencies = []` — uv resolve 비용이 사실상 0. 실측 verify 전체가 2.5초. 추측성 지적 |
| RJ-9 | deepseek #5 | `.ps1` 런처에 에러 시 `pause` 누락 | 기존 9종 런처 전부 `.ps1`에 pause 없음 — 패밀리 관례(autoqa.ps1/autofix.ps1 실측). qwen 1차도 "플랫폼별 관례 준수"로 평가. doctor만 바꾸면 오히려 일관성 파괴 |
| RJ-10 | deepseek #9 | 래퍼 `+x` 퍼미션 미확인 | deepseek 스스로 본문에서 반박한 대로, 래퍼는 `bash`(autofix.py:172,277)/`cmd`/`powershell` 경유 실행이라 +x 무관. PATH 항목은 which가 실행 가능만 반환 |
| RJ-11 | minimax P2-8(3차) | `Path.home()`이 HOME 미설정 시 `/root` 폴백 | **전제 오류.** `os.path.expanduser`는 HOME 미설정 시 `pwd.getpwuid(os.getuid()).pw_dir`(passwd DB)로 폴백해 **실제 사용자 홈**을 반환. "/root로 간다"는 root로 실행할 때뿐이고 그때는 /root가 맞는 홈 |

**자진 철회 1건 (분류 제외)**: minimax P2-4(빈 잠금 파일/garbage 라인 ungraceful) — minimax가 재현 검증 후 "정상 동작 확인 — 삭제"로 스스로 철회. 판정 모수에서 제외.

---

## 4. 최종 수정 계획 — 14개 항목, 수용 지적 29건 100% 커버

### 커버리지 매핑 테이블

| 계획 항목 | 내용 | 우선순위 | 커버 지적 (원본 ID) | 커버 수 |
|---|---|---|---|---|
| **M1** | `core.peek_lock(repo) -> dict \| None` public API 추출 — `ValueError`/`IsADirectoryError`/`OSError` 방어, doctor·autoqa·autofix·`acquire_lock` 공용화 | **P0** | qwen P0-1, minimax P0-1, minimax P0-2, minimax P2-2 | **4** |
| **M2** | `core.is_lock_reclaimable()` 추출 — `AUTOQAFIX_LOCK_STALE_SEC` 반영해 doctor/acquire_lock 판정 통일 | **P0** | gemini ④, minimax P1-1(3차) | **2** |
| **M3** | verify에 lock 시나리오 6종 추가 (없음/alive/dead/cross-host stale/비정상 pid/디렉터리) — M1·M2 회귀 잠금 | **P0** | minimax P1-2(3차) | **1** |
| **M4** | 빈 `AUTOQAFIX_WRAPPERS` → `or WRAPPERS_DEFAULT` 폴백 + 빈 값 WARN | **P1** | qwen T1-2, minimax P2-3(3차) | **2** |
| **M5** | `run_pings` 플랫폼 분기 — `.sh`/`.ps1`/`.bat` ping 3종 탐색 + OS별 인터프리터 선택 | **P1** | gemini ③ | **1** |
| **M6** | 런처 12종의 `.bat`/`.ps1` uv 설치 안내를 `irm …/install.ps1 \| iex`로 교체 | **P1** | gemini ⑥ | **1** |
| **G1** | preflight ⑦과 `check_skills` 중복 FAIL dedupe (`tdd`만 추가 검사) | P2 | gemini ①, deepseek #1 | **2** |
| **G2** | usage 중복 실행 제거 — doctor가 확인한 usage를 select-llm 검사에 재활용 또는 `sys.executable` 직접 실행 | P2 | gemini ②, minimax P2-1(3차) | **2** |
| **G3** | `parse_wrapper_spec`을 `autoqafix_core`로 이동 | P2 | deepseek #7 | **1** |
| **G4** | `check_deploy` glob 의도 주석("env는 플레이스홀더") + verify에 `deploy-to-dev.sh` 감지 케이스 | P2 | minimax P1-4(부분), deepseek #2, deepseek #10 | **3** |
| **G5** | verify 보강 묶음 — select-llm none 분기·스크립트 부재·wrapper `.ps1` 단독·`.bat` pause 비대칭·`out_ok` 범위 주석 | P2 | deepseek #3, qwen T1-3, minimax P1-3(3차), minimax P2-5(3차), minimax P2-7(3차) | **5** |
| **G6** | `run_pings`/`check_wrappers` 폴백 정책 정렬 + 의도 주석 | P3 | qwen P2-1, deepseek #6 | **2** |
| **G7** | preflight 메시지 계약 공식화 (`fail_preformatted` 결합 해소) | P3 | qwen P2-3 | **1** |
| **G8** | 문서화 — design.md 진단 절 + preflight 계수 방식 docstring 명시 | P3 | minimax P2-6(3차), deepseek #8 | **2** |
| **합계** | **14개 항목** | | | **29** |

### 매핑 검산

- 수용 지적 29건(must 10 + good 19) = 계획 항목 커버 합계 29건 → **누락 0, 중복 계수 0**
- reject 11건 + 자진 철회 1건은 설계상 미커버 (단 RJ-1의 재발 방지가 G4 주석으로 부수 해소됨)
- 항목당 평균 커버 2.07건, 최대 G5(5건)·M1(4건)

---

## 5. 판정 총평

1. **가장 위험한 것은 여전히 lock 계열이다.** P0 크래시 2건이 모두 exit 0으로 "정상 종료를 가장"하고, 이를 잡을 verify 커버리지가 0%다. M1~M3은 한 묶음으로 최우선 처리해야 하며, M1은 `acquire_lock`의 동일 잠복 버그까지 함께 해소한다(issue-16 "기존 버그 함께" 원칙).
2. **리뷰 신뢰도는 재현 여부와 정비례했다.** 전 항목을 재현한 minimax3(92%)와 코드를 실측한 gemini35(83%)가 상위, 추정 위주였던 qwen36(45%)이 최하위. qwen 기각 6건은 모두 "코드를 실행/대조하면 즉시 반증되는" 유형이었다.
3. **같은 코드를 두고 4개 리뷰가 3가지로 갈린 deploy glob**(dead code / spec drift / 긍정적 확장)은 코드가 아니라 주석 부재의 문제 — G4가 정답이다.
4. **Windows 계열 must-fix 3건(M5·M6 + 관련)은 gemini만 발견했다.** 크로스 플랫폼 지적은 Linux CI만으로는 재현이 안 되므로, 이후 리뷰 사이클에서 별도 렌즈로 유지할 가치가 있다.
