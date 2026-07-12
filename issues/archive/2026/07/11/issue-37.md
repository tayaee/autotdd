# issue-37: spec 문서 경로 규약 확정 — docs/spec-*.md → docs/spec/spec-*.md
agent-tier: any

## 배경

issue-36에서 spec 산출물 경로를 플랫형 `docs/spec-*.md`로 반영했으나,
사용자 확정으로 중첩형 `docs/spec/spec-*.md`로 변경한다. 기존
`docs/adr/adr-*.md`, `docs/sdd/sdd-*.md`와 동일한
「디렉토리 + 접두사」 패턴으로 통일된다.

**선행**: issue-36 (완료, 6281df6).

## 요구사항

1. `README.md` Quickstart 2줄 — `docs/spec-*.md`를 `docs/spec/spec-*.md`로
   교체 (64행 grill-with-docs 안내, 65행 /to-spec 안내).
2. `regression-tests/verify-issue-36.sh` — README 규약 검사 패턴을
   `docs/spec/spec-*.md`로 갱신 (issue-34가 verify-issue-21.sh를 갱신한
   것과 같은 유형; 검사 의미는 보존, 경로만 최신 규약으로).
3. `issues/issue-*.md`(to-tickets), `docs/adr/adr-*.md` 규약은 변경 없음.

## 승인 기준

- [ ] `grep -c 'docs/spec/spec-\*\.md' README.md` ≥ 2
- [ ] README에 플랫형 `docs/spec-*.md` 잔존 0건
- [ ] `bash regression-tests/verify-issue-36.sh` PASS (갱신된 패턴으로)
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-37.sh` 작성: grep 기반 — README에 중첩형
경로 2회 이상 존재, 플랫형 부재, verify-issue-36.sh 1회 실행해 PASS 확인.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T21:52:00-0400
- **변경 파일**:
  - `README.md` (Quickstart 2줄: `docs/spec-*.md` → `docs/spec/spec-*.md`),
  - `regression-tests/verify-issue-36.sh` (README 규약 검사 패턴을 중첩형으로
    갱신 + 경위 주석),
  - `regression-tests/verify-issue-37.sh` (중첩형 ≥2회·플랫형 부재·
    verify-issue-36 재실행 3개 검사).
- **계획과 차이**: 없음.
- **검증 결과**: verify-issue-37.sh 3 PASS / 0 FAIL (red→green 확인).
  전체 회귀 34/34 PASS.
- **잔여 작업**: 없음. `.claude/skills/` 내 파일 변경이 없어 전역 설치본
  동기화(npx skills update -g) 불필요.
