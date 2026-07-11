# issue-31: doctor 계약·문서화 정리 — 폴백 정책, preflight 메시지 계약, design.md
agent-tier: paid-only
구현 완료 일시: (미정)

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` G6+G7+G8,
원 지적: qwen P2-1/P2-3, deepseek #6/#8, minimax P2-6(3차)).

- `run_pings`는 `AUTOQAFIX_WRAPPER_DIR` → 스킬 `wrappers/` 이중 폴백(구현
  결과에 문서화된 의도), `check_wrappers`는 dir ∨ PATH — 두 검사의 경로
  결정 규칙이 비대칭인데 코드에 이유가 없다.
- doctor `fail_preformatted`가 `core._msg()`의 `[원인]\n[조치]` 2줄 포맷에
  암묵 의존 — preflight 반환 메시지가 공식 계약이 아니다.
- `docs/autoqafix-design.md`에 doctor 언급 0건(cheatsheet만 갱신됨),
  preflight role 단위 FAIL 계수 방식이 출력 포맷 명세에 없다.

**선행**: issue-24 완료 후 착수 (design.md가 최종 lock 진단 정책을 기술해야 함).

## 요구사항

1. `run_pings`/`check_wrappers`의 경로 결정 규칙에 의도 주석 추가 — 두
   정책이 다른 이유(래퍼는 PATH 실행 가능, ping은 스킬 배포물)를 명시.
   정렬이 더 단순하면 정렬해도 되나 기존 테스트 주입 경로(구현 결과 ②)는
   불변
2. preflight 반환 메시지 계약 공식화 — `preflight()` docstring에 "각
   메시지는 `[원인]…\n[조치]…` 2줄" 계약을 명시하고 doctor
   `fail_preformatted` docstring이 이를 참조. (구조화 반환으로의 대규모
   리팩토링은 범위 밖 — 문서화 우선)
3. `docs/autoqafix-design.md`에 "진단 (autoqafix-doctor)" 절 추가: 검사
   7항목 + `--ping` + exit 규약 + lock 회수 판정이 `acquire_lock`과 단일
   소스(issue-24 결과)임을 요약
4. doctor 모듈 docstring에 preflight role 단위 FAIL 계수 방식 1줄 명시

## 승인 기준

- [ ] design.md에 doctor 절 존재 (`grep -i doctor docs/autoqafix-design.md` ≥ 1)
- [ ] preflight/fail_preformatted docstring에 메시지 계약 상호 참조
- [ ] run_pings/check_wrappers 폴백 주석 존재, 동작 회귀 없음
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-31.sh` 작성: grep 기반 — design.md doctor 절,
docstring 계약 문구, 폴백 주석 존재 + 기존 doctor 스모크(픽스처 exit 0) 1회.

## 구현 결과

* **구현 완료 일시**: 2026-07-11T17:25:00-04:00
* **변경 파일**:
  * `.claude/skills/autoqafix/autoqafix_core.py` (`preflight()` docstring에 메시지 계약 문구 — `"[원인] ...\n[조치] ..."` 2줄 — 정식화)
  * `.claude/skills/autoqafix/autoqafix-doctor.py` (모듈 docstring에 preflight role 단위 FAIL 계수 1줄 + `check_wrappers`/`run_pings`에 비대칭 경로 결정 의도 docstring + `fail_preformatted` docstring에 preflight docstring 상호 참조 + 모듈 경로 명시)
  * `docs/autoqafix-design.md` (`## 진단 (autoqafix-doctor)` 절 신규 — 검사 7항목 + `--ping` 비대칭 + exit 규약 + lock 단일 소스 = issue-24 결과)
  * `regression-tests/verify-issue-31.sh` (신규 — design.md 키워드 11건 + preflight docstring 3건 + fail_preformatted 상호 참조 2건 + 모듈 docstring 2건 + 폴백 의도 4건 + doctor 스모크 회귀 1건 = 25개 검증)
* **계획 대비 변경 사항**: 없음 (요구사항 1~4 그대로 수행). 비대칭 이유는 두 가지로 정리 — (a) 래퍼는 시스템 전역 도구처럼 외부 자원이므로 PATH 폴백 OK, (b) ping은 스킬 내부 진단 자원이므로 PATH 추적 불가 → 폴백 없음.
* **검증 결과**:
  * `verify-issue-31.sh` PASS — 25개 검증 모두 통과 (design.md 12 / preflight docstring 3 / fail_preformatted 2 / 모듈 docstring 2 / 비대칭 의도 4 / 기존 doctor 스모크 2)
  * `verify-issue-20/24/25/26/27/28/29/30.sh` PASS — 회귀 자산 모두 불변
  * ruff: All checks passed (tool run)
  * pyright (전체 프로젝트): 0 errors, 0 warnings, 0 informations
  * `python3 -m py_compile` clean (core/doctor 둘 다)
  * preflight `_msg` 계약 회귀 잠금 — `[원인] X\n[조치] Y` 정확 출력 확인
  * 전체 회귀 테스트: PASS=25 FAIL=0 (이슈-31 신규 + 이슈-20/24~30 8개 기존 = 9개 스크립트 합산)
