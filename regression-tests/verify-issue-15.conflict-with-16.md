# verify-issue-15 ↔ issue-16 충돌 해소 기록

- **작성 일시**: 2026-07-11 (issue-16 재작업 중)
- **대상**: `regression-tests/verify-issue-15.sh`

## 무엇이 바뀌었나

issue-15의 dispatch는 스텁이었다: `DISPATCH <item> <래퍼>` 한 줄을 stdout에
출력하고 항상 `FIXED=0`. verify-issue-15.sh는 그 스텁의 출력 문자열과
bare-name(`claudecli`) PATH 실행을 그대로 기대했다.

issue-16이 스텁을 실구현으로 교체하면서 (의도된 동작 변경):

1. `DISPATCH ...` stdout 라인이 사라짐 — 성공 판정은 pull 후
   `issues/archive/**` 존재로 바뀜.
2. `FIXED=<n>`이 고정 0에서 실계수로 바뀜.
3. 래퍼 실행이 `bash $AUTOQAFIX_WRAPPER_DIR/<name>.sh`로 바뀜
   (bare-name PATH 의존은 리뷰 A-3에서 프로덕션 즉사 결함으로 판정).

그러나 issue-16 작업 시 verify-issue-15.sh 갱신(tdd2 step 9(b))이 누락되어,
이후 main의 전체 회귀 게이트가 항상 실패했다 (issue-19 런에서 발견).

## 어떻게 갱신했나

스켈레톤 검증 의도(필터링, manual rename, tier 스탬프, tier 매칭, 사람
main tree 불변, worktree 생성)는 유지하되, 관찰 지점을 스텁 출력에서 실
dispatch 결과(archive 존재 여부)로 교체:

- `DISPATCH ...` grep → `issues/archive/**/<item>.md` 존재/부재 확인
- `FIXED=0` 고정 기대 → 시나리오 A `FIXED=2`, B `FIXED=1`
- 시나리오 B는 A가 항목을 archive로 소모하므로 별도 픽스처에서
  autofix-2를 `agent-tier: local-ok`로 pre-stamp 후 실행
- fake wrapper는 tier 판정 호출(항목 본문)과 dispatch 호출(`/autotdd ...`
  프롬프트)을 구분해, 후자를 `lib/fake-wrapper.sh`의 archive 모드로 위임

dispatch 자체의 실패/타임아웃/복구 동작은 verify-issue-16.sh의 소관
(TEST 1–6)이며 이 스크립트는 중복 검증하지 않는다.
