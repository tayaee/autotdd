# issue-30: doctor verify 보강 묶음 + deploy glob 의도 명시
agent-tier: paid-only
구현 완료 일시: (미정)

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` G4+G5,
원 지적: deepseek #2/#3/#10, qwen T1-3, minimax P1-3/P2-5/P2-7(3차)).
verify-issue-20.sh가 happy path 위주라 기능 분기 다수가 회귀 잠금 없이
남았다. 또한 `check_deploy`의 `deploy-to-*` glob은 스펙 `deploy-to-env`의
"env"를 환경명 플레이스홀더로 해석한 **올바른 구현**이지만, 4개 리뷰 중
3개가 서로 다르게 오독했다(dead code / spec drift / 긍정적 확장) —
주석 부재가 원인. glob을 좁히지 말고 의도를 명시한다.

## 요구사항

1. `check_deploy`에 의도 주석 추가: 스펙의 `deploy-to-env`에서 env는
   환경명 플레이스홀더이며 glob은 진단 **대상 repo**의
   `deploy-to-<env>.{sh,ps1,bat}`를 감지한다는 취지 (glob 변경 금지)
2. 신규 verify에 다음 케이스 추가 (기존 verify-issue-20.sh는 회귀 자산
   으로 유지, 신규 케이스는 verify-issue-30.sh에):
   - `deploy-to-dev.sh`만 있는 픽스처 → `OK deploy 스크립트`
   - select-llm이 `none`을 내는 환경(가용 래퍼 0) → `OK select-llm (none)`
   - `select-llm.py` 부재 → 크래시 없이 `FAIL select-llm`
   - `.ps1` 단독 래퍼(`<name>.ps1`만 존재) → `OK 래퍼 <name>`
   - `.bat` 런처 pause 비대칭 회귀 잠금 — PASS 경로에 pause가 없고
     오류 분기에만 있음을 검사 (`grep -q pause` 단순 존재 검사 초과)
3. `verify-issue-20.sh`의 TEST 8이 TEST 5의 `out_ok`를 재사용하는 암묵
   의존에 범위 주석 추가 (동작 변경 없이 주석만)

## 승인 기준

- [ ] 위 5개 신규 케이스가 verify-issue-30.sh에서 각각 독립 PASS
- [ ] `check_deploy` 주석 존재, glob 동작 불변
- [ ] verify-issue-20.sh는 주석 외 무변경, 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-30.sh` 작성: 요구사항 2의 케이스 전부 +
주석 존재 grep(요구사항 1·3).

## 구현 결과

* **구현 완료 일시**: 2026-07-11T13:17:23-04:00
* **변경 파일**:
  * `.claude/skills/autoqafix/autoqafix-doctor.py` (check_deploy 의도 주석 — glob 정책 변경 없이 docstring 확장)
  * `regression-tests/verify-issue-20.sh` (TEST 8에 TEST 5 out_ok 재사용 범위 주석)
  * `regression-tests/verify-issue-30.sh` (신규 — 5 케이스 + 정적 주석 3종)
* **계획 대비 변경 사항**: 없음 (verify-issue-30.sh의 `set +e / set -e` 패턴은 기존 verify-issue-*.sh 관례 따름)
* **검증 결과**:
  * `verify-issue-30.sh` PASS — 11개 검증 모두 통과 (정적 주석 3건, 신규 5 케이스 A/B/C/D/E, .bat pause 비대칭 회귀 잠금 2건)
  * `verify-issue-20.sh` PASS — 회귀 자산 동작 불변 (TEST 8 out_ok 재사용 명시 후에도 동일 통과)
  * ruff: All checks passed (tool run)
  * pyright (전체 프로젝트): 0 errors, 0 warnings, 0 informations
  * `uv run python -m compileall`: clean
  * 전체 회귀 테스트: PASS=24 FAIL=0 (이슈-30 신규 포함)
