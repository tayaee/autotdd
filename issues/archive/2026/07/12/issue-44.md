# issue-44: review-stats 스키마 보강 — 리뷰어 model 필드 + 중복 finding 전원 크레딧 명시
agent-tier: any

## 배경

2026-07-12 그릴링에서 "장기 누적으로 리뷰어 능력을 평가할 데이터가 되는가"를
점검한 결과, 확정된 결정:

- coder 축은 같은 날 후속 그릴링에서 **기록하기로 번복**됨 — 단 데이터
  소스가 달라(정적분석 카운트·LOC) 별도 이슈 issue-45로 분리. 본 이슈는
  리뷰어 축만 다룬다.
- **승격률(플래너 판정)이 리뷰어 평가의 정본** — 사람의 파킹 승격/방치는
  지표에 반영하지 않음 (CONTEXT.md "승격률" 항목으로 기록됨, 본 커밋에 포함).
- 남은 구멍 2건이 본 이슈의 대상:
  1. stats JSON 리뷰어 키가 base명뿐이라 래퍼 뒤 모델이 업그레이드되면
     (예: sonnet 4→5) 전후 이력이 한 줄에 섞여 나중에 가를 수 없다.
  2. 여러 리뷰어가 같은 결함을 독립 발견했을 때 must_fix 크레딧 배분이
     SKILL.md에 명시돼 있지 않아 플래너 재량에 따라 승격률이 흔들린다.

**선행**: issue-41 (스키마·기록), issue-43 (스코어보드 CLI).

## 요구사항

1. **`model` 필드 추가** (`.claude/skills/autotddreview/SKILL.md` Step 3-7):
   review-stats JSON의 `reviewers` 각 항목에 `model` 필드를 필수로 추가 —
   플래너가 해당 리뷰 파일 **첫 줄의 버전 포함 모델명**을 그대로 전사한다.
   키는 base명 유지(스코어보드 집계 단위 불변). 첫 줄에서 모델명을 얻지
   못하면 `"unknown"`을 기록한다(침묵 금지).
2. **전원 크레딧 명시** (같은 파일 Step 3): 복수 리뷰어가 같은 결함을 독립
   발견해 승격되면 — 파생 이슈는 **1개만** 생성(계보에 복수 리뷰 파일 인용),
   stats의 must_fix/good_to_fix 카운트는 **발견한 리뷰어 전원에게 각각 +1**.
   최초 발견자 개념 없음(병렬 실행이라 무의미).
3. **스코어보드 호환 확인**: `tools/reviewer-scoreboard.py`가 `model` 필드가
   있는 stats JSON을 기존과 동일하게 집계하는지(미지 필드 무시) 테스트로
   고정한다. CLI 코드 변경은 무시가 깨져 있을 때만.
4. **품질**: ruff+pyright+pytest 통과.

## 승인 기준

- [ ] SKILL.md Step 3-7 필수 필드 목록에 리뷰어별 `model`(버전 포함 전사,
      실패 시 `"unknown"`) 명시
- [ ] SKILL.md Step 3에 중복 finding 규칙(파생 이슈 1개 + 전원 크레딧) 명시
- [ ] `model` 필드 포함 픽스처로 scoreboard 집계 불변 테스트 존재·통과
- [ ] ruff+pyright+pytest 통과, 전체 회귀 PASS

## 검증

`regression-tests/verify-issue-44.sh`:
- SKILL.md에서 `model` 필드 규정과 전원 크레딧 규칙 문구를 grep으로 단언.
- `model` 필드가 든 픽스처 stats JSON을 임시 디렉토리에 만들어
  `tools/reviewer-scoreboard.py --json` 실행 — 집계 결과가 `model` 없는
  기존 픽스처와 동일 수치인지 단언.

## 구현 결과

**구현 완료 일시**: 2026-07-12T00:00:00Z
**변경 파일**:
- `.claude/skills/autotddreview/SKILL.md` — Step 3-5에 중복 finding 전원 크레딧 규칙 추가, Step 3-7의 reviewers 필수 필드에 `model` 추가 + 첫 줄 전사·unknown 폴백·침묵 금지 명시
- `tests/test_reviewer_scoreboard.py` — `model` 필드가 집계에 영향 없음을 고정하는 단위 테스트 2건 추가
- `regression-tests/verify-issue-44.sh` — 신규. SKILL.md grep + model 필드 들/없는 픽스처로 집계 불변 단언 + 단위 테스트 게이트

**스펙 이탈**: 없음.

**verify 결과**: `bash regression-tests/verify-issue-44.sh` — 11/11 PASS. 전체 회귀 41/41 PASS. `uv run --with pytest pytest -q tests/` 8/8 PASS.
