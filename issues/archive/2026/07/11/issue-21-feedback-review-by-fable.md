# issue-21 리뷰 피드백 종합 판정 (by Fable 5)

- **판정 일시**: 2026-07-11
- **대상**: `issue-21-code-review-by-{gemini35,sonnet5,qwen36}.md` (작성 순서: gemini35 14:23 → sonnet5 14:38 → qwen36 15:04)
- **판정 기준 커밋**: `0cf8961` (issue-21: Claude Code 트리거 스킬 4종 + install.sh)
- **판정 방법**: 3개 리뷰의 전 지적사항을 실제 코드(`.claude/skills/{autoqa,autofix,autodev,autoqafix}/SKILL.md`, `install.sh`, `regression-tests/verify-issue-21.sh`, 엔진 `.claude/skills/autoqafix/{autoqa,autofix,error-to-autofix,autoqafix-doctor}.py`)와 대조·재실측하여 must-fix / good-to-fix / reject로 분류

---

## 0. 총괄 (두괄식 요약)

- **총 지적사항 22건** (원본 지적 단위, 리뷰 간 중복 재확인 포함)
- **분류 결과**: must-fix **8건** / good-to-fix **9건** / reject **5건** → **전체 수용률 77%** (17/22)
- **최종 수정 계획: 이슈 3건** (`issues/issue-32.md` ~ `issues/issue-34.md`)이 **수용 지적 17건 전부를 커버** (커버율 100%)
- **보고서별 유효성**: sonnet5 100% > qwen36 78% > gemini35 50%
- **최중요 결론**: **`/autodev` 트리거는 현재 아예 동작하지 않는다** (존재하지 않는 `autodev.py` 호출). 13/13 PASS는 "문서 형식"만 보증했고, 회귀 테스트가 엔진 경로 실존을 검사하지 않아 이 결함이 병합됐다 — issue-16/issue-20에서 반복된 "verify PASSED여도 검증력 빈 검사 주의" 함정의 재발이다.

### 보고서별 집계

| 보고서 | 총 지적 | must-fix | good-to-fix | reject | 수용률 | 유효성 평가 |
|---|---|---|---|---|---|---|
| 1차 gemini35 | 6 | 0 | 3 | 3 | **50%** | must-fix 발굴 0건 — SKILL.md와 엔진 코드를 대조하지 않아 P0 2건을 모두 놓침. 다만 verify의 빈 no-op 루프·중복 실행·`set -e` 부재는 **최초 발견** (GF 3건 전부 gemini가 시조) |
| 2차 sonnet5 | 7 | 4 | 3 | 0 | **100%** | **P0(`autodev.py` 부재) 최초 발견** + "테스트가 왜 이걸 못 잡았나"(엔진 경로 실존 미검증)라는 구조적 결함을 유일하게 지적. dangling symlink 오판도 직접 재현. 오판 0건 |
| 3차 qwen36 | 9 | 4 | 3 | 2 | **78%** | sonnet 후행이지만 전 항목을 grep/실행으로 독립 재검증했고, autoqa의 "완전 무출력"을 P0로 승격 제시한 정밀도가 돋보임. 기각 2건(상대경로 symlink, 한글 정규식)은 추측성 |
| **합계** | **22** | **8** | **9** | **5** | **77%** | |

---

## 1. must-fix — 실수 인정 (8건 → 결함 단위 4행)

| # | 출처 | 지적 | 인정 근거 (실측) |
|---|---|---|---|
| MF-1 | sonnet 2.1, qwen 2.1 | `autodev/SKILL.md`가 존재하지 않는 `<엔진 폴더>/autodev.py`를 실행하라고 지시 — `/autodev` 트리거가 **항상 즉시 실패** | 재실측 확인: `ls .claude/skills/autoqafix/*.py`에 `autodev.py` 없음, `grep -rn 'autodev\.py'`는 SKILL.md 2줄뿐. 실제 dev 스트림 진입점은 `autofix.py --stream issue` (`autodev.sh` 레거시 런처 및 autofix.py docstring이 명시) |
| MF-2 | qwen 2.2, qwen 3.1, sonnet 3.1 | `autoqa`/`autofix`/`autodev` 3개 SKILL.md의 4단계 "출력 요약 보고" 토큰 계약(`[원인]`/`[조치]`/`FIXED=`/`FAIL`/`OK`)이 실제 엔진 stdout과 불일치 | 재실측 확인: `autoqa.py`+`error-to-autofix.py`는 해당 토큰 매치 0건(stderr+exit code뿐), `autofix.py` stdout은 `처리: N건, …` + `FIXED=<n>` 2줄뿐. 토큰 계약은 `autoqafix-doctor.py`(47–66행) 고유 출력을 복붙한 것 — 4개 중 `autoqafix`만 문서와 일치 |
| MF-3 | sonnet 2.2 | verify-issue-21.sh가 frontmatter·문구 존재만 정규식으로 검사하고 SKILL.md가 참조하는 엔진 스크립트의 실존은 미검증 — MF-1이 13 PASS로 병합된 구조적 원인 | 재실측 확인: `grep -n '엔진 실행\|uv -q run' verify-issue-21.sh` 매치 0건. issue-20 MF-4(lock 검증 0%)와 동일 유형의 "빈 검사" 함정 |
| MF-4 | sonnet 3.2, qwen 3.2(부분) | install.sh가 깨진(dangling) symlink도 `[ -L "$dst" ]`만 보고 "이미 설치됨"으로 성공 처리(exit 0) — repo 이동/재클론 시 조용히 깨진 채 복구 불가 | 재실측 확인: install.sh 37–43행은 `readlink`로 target을 출력만 하고 resolve 가능 여부를 검사하지 않음. 진단·복구 수단이 없는 침묵 실패는 issue-20 MF-5(오설정 침묵 통과)와 동일 양식의 실수 |

> 원본 지적 단위 8건(sonnet 4 + qwen 4)이 결함 단위 4행으로 묶임.

## 2. good-to-fix — 개선 수용 (9건 → 개선 단위 3행)

| # | 출처 | 지적 | 수용 사유 |
|---|---|---|---|
| GF-1 | gemini 3.1.1, qwen 3.2(부분), sonnet 4 | install.sh에 `set -e` 부재 (`set -uo pipefail`만) — `mkdir -p`/`ln -s` 실패에도 계속 진행해 잘못된 요약·exit 0 가능 | 사실 확인(install.sh:11). MF-4와 합치면 "실패를 감지 못 하고 성공 보고" 패턴이 2곳 — 함께 수정 |
| GF-2 | gemini 3.2.1, qwen 4.1, sonnet 4 | verify-issue-21.sh 144–151행 "실 HOME 오염 검증" 루프가 `:` no-op뿐인 빈 껍데기 + 144행 `${HOME:-$HOME}`은 문법상 무의미 | 사실 확인. 격리 자체는 fake HOME으로 구조적으로 보장되므로 위험도는 낮으나, 검증하는 척하는 죽은 코드는 "빈 검사" 교훈상 제거 또는 실검증화 필요 |
| GF-3 | gemini 3.2.2, qwen 4.1, sonnet 4 | 92/106행에서 이미 install.sh를 2회 실행하고도 exit code만 얻으려고 112–113행에서 3·4차 재실행 | 사실 확인. 1·2차 실행 시점에 rc를 캡처하면 제거 가능 — issue-29의 "usage 중복 실행 제거"와 같은 유형 |

> 원본 지적 단위 9건(gemini 3 + qwen 3 + sonnet 3)이 개선 항목 3행으로 묶임.

## 3. reject — 반박 (5건)

| # | 출처 | 지적 | 반박 근거 (실측) |
|---|---|---|---|
| RJ-1 | gemini 3.1.2, qwen 3.3 | 절대경로 symlink는 repo 이동 시 깨지므로 상대경로(`ln -s --relative`) 권장 | **해법이 문제를 못 푼다.** `~/.claude/skills/<name>` → repo 상대경로도 repo가 이동하면 똑같이 깨진다(도움이 되는 건 HOME 상위 경로 개명처럼 두 경로가 함께 움직이는 극단 케이스뿐). 실 시나리오(repo 이동/재클론)의 올바른 해법은 MF-4의 dangling 감지+재연결이며, 그것으로 이 지적의 실익이 소멸. gemini 스스로 "absolute가 가장 안전한 fallback"이라 후퇴 |
| RJ-2 | gemini 3.1.3 | `--force` 플래그로 기존 링크/파일 강제 덮어쓰기 옵션 제공 | 결함이 아닌 기능 제안. 타 프로젝트 스킬이 점유한 이름을 지우고 덮어쓰는 force는 오히려 사고 경로 — 현재의 WARN+수동 정리가 의도된 안전 기본값(install.sh 주석에 명시). 실수요가 생기면 그때 별도 이슈 |
| RJ-3 | gemini 3.2.3, qwen 4.1 | 금지 문구 검사 정규식이 한국어 전용 — 향후 영문 번역 시 오작동 | 추측성(YAGNI). 이 repo의 SKILL.md는 의도적으로 한국어 단일이고 다국어화 계획이 없다. 테스트의 목적은 **현재 계약**의 잠금이며, 계약 문구가 번역되면 그 이슈에서 테스트도 함께 바뀌는 것이 정상. 지금 영문 패턴을 추가하면 오히려 "한국어 문구가 사라져도 통과"하는 검증력 약화 |

---

## 4. 최종 수정 계획 — 이슈 3건, 수용 지적 17건 100% 커버

to-issues 방식의 수직 슬라이스로 분할 — 각 이슈는 단독으로 구현·검증·병합 가능하다.

| 이슈 | 내용 | 우선순위 | 커버 지적 (원본 단위) | 커버 수 |
|---|---|---|---|---|
| **issue-32** | SKILL.md ↔ 엔진 계약 정합화 — `/autodev` 엔진 실행을 `autofix.py --stream issue`로 수정(MF-1) + 3개 스킬의 출력 계약을 실제 stdout에 맞게 재작성(MF-2) + 엔진 경로 실존·출력 계약 대조 회귀 검사 신설(MF-3) | **P0** | sonnet 2.1·2.2·3.1, qwen 2.1·2.2·3.1 | **6** |
| **issue-33** | install.sh 견고화 — dangling symlink 감지·재연결(MF-4) + `set -e` 추가(GF-1), dangling 시나리오 회귀 테스트 포함 | **P1** | sonnet 3.2·4(set-e), qwen 3.2×2, gemini 3.1.1 | **5** |
| **issue-34** | verify-issue-21.sh 정리 — 빈 no-op 루프 실검증화 또는 제거 + `${HOME:-$HOME}` 정리(GF-2), rc1/rc2 중복 실행 제거(GF-3) | **P2** | gemini 3.2.1·3.2.2, qwen 4.1×2, sonnet 4×2 | **6** |
| **합계** | | | | **17** |

### 매핑 검산

- 수용 지적 17건(must 8 + good 9) = 이슈 3건 커버 합계 17건 → **누락 0**
- reject 5건은 설계상 미커버 (단 RJ-1의 실 시나리오는 issue-33의 self-heal로 부수 해소)

---

## 5. 판정 총평

1. **"13/13 PASS" 아래에 동작 불능 트리거가 숨어 있었다.** verify가 문서 형식만 검사한 탓에 `/autodev`는 실행 즉시 실패하는 상태로 병합됐다. issue-20 판정 때 "verify PASSED여도 검증력 빈 검사 주의"를 교훈으로 남겼는데 같은 커밋 사이클에서 재발한 셈 — issue-32의 회귀 검사(엔진 경로 실존 + 출력 계약 대조)가 이 유형을 구조적으로 잠근다.
2. **리뷰 신뢰도는 이번에도 "대조·재현 여부"와 정비례했다.** 엔진 코드를 직접 대조한 sonnet5(100%)·qwen36(78%)이 P0를 찾았고, 대상 파일만 읽은 gemini35(50%)는 must-fix를 하나도 못 찾았다. issue-20의 결론(minimax 92% > … > qwen 45%)과 동일 패턴.
3. **복붙이 만든 계약 허위가 가장 넓게 퍼진 결함이다.** doctor 고유의 출력 토큰이 4개 스킬 중 3개에 그대로 복제됐다(MF-2). 스킬 문서는 LLM에게 내리는 실행 지시이므로, 문서-코드 불일치는 곧 오동작 지시다 — 이후 스킬 작성 시 "출력 계약은 엔진 stdout을 grep으로 실측한 뒤 기재"를 관례로 삼을 것.
4. **install.sh의 침묵 실패 2종(MF-4 + GF-1)은 한 몸이다.** "존재만 확인하고 유효성은 확인 안 함" + "에러가 나도 계속 진행" — 둘 다 실패를 성공으로 보고하는 패턴이라 issue-33에서 함께 수정한다.
