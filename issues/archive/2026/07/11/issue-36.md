# issue-36: mattpocock skills 1.1 개명 반영 — to-issues→to-tickets, to-prd→to-spec
agent-tier: any

## 배경

이 리포가 배포하는 스킬(autotdd/autorevfix 등)은 mattpocock/skills를 확장
재사용하며, 사용자는 README의 안내대로 mattpocock 스킬을 함께 설치한다.
mattpocock/skills가 1.0→1.1로 올라가며 두 스킬이 개명되었다:

- `to-prd` → `to-spec` (산출물: spec/PRD 문서)
- `to-issues` → `to-tickets` (산출물: 티켓/이슈 파일)

업스트림에서 구 이름 스킬은 삭제되었다 (`npx skills check -g`가
"deleted upstream" 경고). 이 리포에는 구 이름 참조가 3곳 남아 있어,
1.1을 설치한 사용자 환경에서 존재하지 않는 스킬을 호출하게 된다:

1. `.claude/skills/autorevfix/SKILL.md:112` — planner 프롬프트가
   `to-issues 스킬로 수정 계획 … 작성해`를 지시
2. `.claude/skills/autotdd/SKILL.md:65` — tdd 미설치 안내문의 형제 스킬
   예시 목록에 `to-issues`, `to-prd` 포함
3. `README.md:64` — Quickstart가 구 규약 `docs/prd/prd-*.md`를 언급

새 규약: spec은 `docs/spec-*.md`에 작성한다. `to-tickets`는 과거
호환성을 위해 이 리포 생태계의 기존 관례인 `issues/issue-*.md` 경로에
작성한다 (autorevfix:112의 프롬프트는 출력 경로를 이미 명시하므로 스킬명
개명만으로 호환 유지).

**선행**: 없음.

## 요구사항

1. `.claude/skills/autorevfix/SKILL.md:112` — `to-issues 스킬로` →
   `to-tickets 스킬로`. 출력 경로
   `issues/issue-<N>-feedback-review-by-<P-version>.md`는 그대로 유지.
2. `.claude/skills/autotdd/SKILL.md:65` — 예시 목록의 `to-issues`,
   `to-prd`를 `to-tickets`, `to-spec`으로 교체.
3. `README.md` Quickstart —
   - 기존 줄의 `docs/prd/prd-*.md`를 `docs/spec-*.md`로 교체
     (`docs/adr/adr-*.md`, `docs/sdd/sdd-*.md`는 유지).
   - 새 워크플로우 안내 줄 추가: `/to-spec`은 `docs/spec-*.md`를,
     `/to-tickets`는 과거 호환 경로 `issues/issue-*.md`를 작성한다는 취지.
4. 아카이브(`issues/archive/`)의 과거 문서는 수정하지 않는다 (기록 보존).

## 승인 기준

- [ ] `grep -rn "to-issues\|to-prd" .claude/skills/ README.md CONTEXT.md docs/`
      매치 0건
- [ ] `.claude/skills/autorevfix/SKILL.md`에 `to-tickets` 존재, 출력 경로
      `issues/issue-<N>-feedback-review-by-<P-version>.md` 보존
- [ ] `.claude/skills/autotdd/SKILL.md`에 `to-tickets`, `to-spec` 존재
- [ ] `README.md`에 `docs/spec-*.md` 규약과 `/to-spec`·`/to-tickets` 안내 존재
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-36.sh` 작성: grep 기반 —
(1) 리포 스킬·README·CONTEXT·docs에 `to-issues`/`to-prd` 문자열 부재
(아카이브 제외), (2) autorevfix에 `to-tickets`+기존 출력 경로 보존,
(3) autotdd에 `to-tickets`·`to-spec` 존재, (4) README에 `docs/spec-*.md`
규약 존재를 검사 (issue-31/34의 grep 기반 verify와 동일 패턴).

## 구현 결과

- **구현 완료 일시**: 2026-07-11T21:38:30-0400
- **변경 파일**:
  - `.claude/skills/autorevfix/SKILL.md` (112행 planner 프롬프트
    `to-issues`→`to-tickets`, 출력 경로는 그대로),
  - `.claude/skills/autotdd/SKILL.md` (65행 형제 스킬 예시
    `to-issues`/`to-prd`→`to-tickets`/`to-spec`),
  - `README.md` (Quickstart: `docs/prd/prd-*.md`→`docs/spec-*.md` 교체 +
    `/to-spec`·`/to-tickets` 워크플로우 안내 줄 추가),
  - `regression-tests/verify-issue-36.sh` (구 이름 부재·새 이름 존재·출력
    경로 보존·README 규약 6개 검사).
- **계획과 차이**: 없음. grill-me 세션에서 합의된 대로 — 아카이브는 보존,
  autorevfix의 출력 경로 명시 덕에 스킬명 개명만으로 과거 호환 유지.
- **검증 결과**: verify-issue-36.sh 6 PASS / 0 FAIL (red→green 확인).
  전체 회귀 33/33 PASS.
- **잔여 작업**: 리포 밖 로컬 환경 정리(승인됨) — `~/.claude/skills/`의
  to-issues/to-prd 실사본 및 `~/.agents/.skill-lock.json` 항목 삭제, 푸시 후
  `npx skills update -g`로 전역 설치본 동기화. aacpd 이후 별도 수행.
