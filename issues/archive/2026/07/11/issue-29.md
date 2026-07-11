# issue-29: doctor 결합도·성능 — parse_wrapper_spec core 이동 + usage 중복 실행 제거
agent-tier: paid-only

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` G3+G2,
원 지적: deepseek #7, gemini ②, minimax P2-1(3차)).

- doctor가 `parse_wrapper_spec()` 하나 때문에 `import autofix`(실행 엔진
  전체)를 전이 의존한다 — 진단 도구가 엔진의 미래 변경/무거운 초기화에
  노출됨.
- usage 스크립트가 중복 실행된다: doctor `check_usage_scripts`가 후보별
  1회 + `check_select_llm`이 띄운 `select-llm.py` 내부 `fetch_usage`가
  같은 스크립트를 다시 1회. 기본 3래퍼 기준 직렬 `uv` 실행 8회
  (doctor 1 + usage 3 + select-llm 1 + 내부 usage 3) — 사전 점검
  도구치고 느리다 (콜드 수 초).

## 요구사항

1. **(prefactor 먼저)** `parse_wrapper_spec()`을 `autoqafix_core.py`로 이동.
   `autofix.py`는 core에서 import(기존 호출부 시그니처 불변), doctor의
   `import autofix` 제거
2. usage 중복 실행 제거 — 방향은 구현 시 선택하되 목표는 "usage
   스크립트가 doctor 1회 실행당 후보별 1회만 기동":
   - (a안) `select-llm.py`가 usage 결과 주입(예: env 또는 인자)을 받으면
     `fetch_usage`를 생략하고, doctor가 `check_usage_scripts`의 결과를
     주입해 호출
   - (b안) doctor가 usage를 `sys.executable`로 직접 실행해 uv 기동 비용
     절감 (usage 3종은 `dependencies = []`라 PEP-723 격리 불필요)
   - a안이 중복 제거까지 되므로 우선 검토, PEP-723 계약을 깨지 않을 것
3. select-llm의 단독 실행(주입 없는 기존 사용)은 동작 불변

## 승인 기준

- [ ] `autoqafix-doctor.py`에 `import autofix` 없음
- [ ] doctor 1회 실행에서 usage-<name>.py가 후보별 정확히 1회만 기동
      (호출 카운트를 기록하는 fake usage 스크립트로 검증)
- [ ] `select-llm.py` 단독 실행(기존 방식) 동작 불변 — exit 0/2 계약 유지
- [ ] 기존 회귀 전체 PASS (autofix의 parse_wrapper_spec 사용처 포함)

## 검증

`regression-tests/verify-issue-29.sh` 작성: ① doctor 소스에 `import autofix`
부재 grep, ② 카운트 파일을 남기는 fake usage로 후보별 1회 기동 확인,
③ select-llm 단독 실행 회귀.

## 구현 결과

* **구현 완료 일시**: 2026-07-11T13:10:30-04:00
* **변경 파일**:
  * `.claude/skills/autoqafix/autoqafix_core.py`
  * `.claude/skills/autoqafix/autofix.py`
  * `.claude/skills/autoqafix/autoqafix-doctor.py`
  * `.claude/skills/autoqafix/select-llm.py`
  * `regression-tests/verify-issue-29.sh`
* **계획 대비 변경 사항**: 없음
* **검증 결과**:
  * `verify-issue-29.sh` PASS (doctor 내 `import autofix` 부재 검증, doctor 기동 시 usage 중복 실행 차단 검증, select-llm.py 단독 실행 시 기존 exit code 및 output 계약 유지 검증 완료)
  * 전체 회귀 테스트 PASS (총 23개 테스트 완료)
