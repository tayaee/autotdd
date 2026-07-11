# issue-25: 빈 AUTOQAFIX_WRAPPERS — default 폴백 + WARN
agent-tier: local-ok

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` M4,
원 지적: qwen T1-2, minimax P2-3). `AUTOQAFIX_WRAPPERS=""`(빈 문자열)로
doctor를 실행하면 `os.environ.get(..., WRAPPERS_DEFAULT)`가 빈 문자열을
default로 폴백하지 않아 `parse_wrapper_spec("") → {}` → wrapper/usage/
select-llm 검사가 통째로 무실행인데 **경고 없이 FAIL 0으로 통과**한다
(minimax 재현 확인). 진단 도구가 오설정 자체를 침묵 통과시키는 결함.

## 요구사항

1. doctor의 spec 결정을 `os.environ.get("AUTOQAFIX_WRAPPERS") or
   WRAPPERS_DEFAULT` 형태로 — 빈 문자열이면 기본 후보로 폴백
2. 폴백 후에도 파싱 결과가 빈 목록이면(예: `AUTOQAFIX_WRAPPERS=":"`)
   `WARN — AUTOQAFIX_WRAPPERS가 비어있음, 래퍼 검사 생략` 출력
   (WARN이므로 exit에는 미반영 — deploy WARN과 동일 정책)
3. `autofix.py` 등 동일한 `os.environ.get(..., default)` 패턴으로 spec을
   읽는 곳이 있으면 같은 폴백으로 일괄 정리 (기존 버그 함께 원칙)

## 승인 기준

- [ ] `AUTOQAFIX_WRAPPERS=""` → 기본 후보 3종으로 wrapper/usage 검사가 수행됨
      (silent skip 없음)
- [ ] 파싱 결과가 빈 spec → WARN 라인 출력, exit code에는 미반영
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-25.sh` 작성: ① 빈 문자열 env에서 기본
후보 검사 수행 확인, ② 무효 spec에서 WARN 출력 + exit 미반영 확인.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T12:52:00-04:00
- **변경 파일**: `.claude/skills/autoqafix/autoqafix-doctor.py`, `.claude/skills/autoqafix/autofix.py`, `.claude/skills/autoqafix/error-to-autofix.py`, `.claude/skills/autoqafix/select-llm.py`, `regression-tests/verify-issue-25.sh`
- **계획과 차이**: 없음
- **검증 결과**: verify-issue-25.sh PASS. 전체 회귀 테스트 통과.
