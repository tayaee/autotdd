# issue-11: 번호 예약 프로토콜
agent-tier: paid-only

## 배경

여러 머신의 agent가 같은 스트림에 동시 보고해도 번호가 충돌하지 않아야 한다.
push 성공을 원자성 장치로 쓴다 (docs/autoqafix-design.md "autoqa" 5번).

## 요구사항

1. `autoqafix_core.py`에 추가:
   - `next_number(repo, stream) -> int`: `issues/` 재귀(archive 포함)에서
     `<stream>-<N>*.md` + `regression-tests/verify-<stream>-<N>.sh`의 최대 N + 1.
     stream은 `issue` 또는 `autofix`
   - `reserve_number(repo, stream, summary, purpose) -> (int, Path)`:
     ① next_number로 후보 N, ② `issues/<stream>-<N>.md`에 두 줄만 기록
     (`# <stream>-<N>: <summary>` + `reported-by: <purpose>@<hostname> <ISO8601>`),
     ③ 그 파일만 add·commit(`<stream>-<N>: 번호 예약`)·push,
     ④ push 거부 시 해당 커밋을 `git reset --hard HEAD~1`로 제거 →
     `git pull --rebase` → N 재계산 → 재시도(최대 10회, 초과 시 예외),
     ⑤ 성공 시 (N, 파일경로) 반환
   - `finalize_item(repo, path, body)`: 예약 파일의 두 줄 뒤에 body를 이어 붙여
     commit(`<stream>-<N>: <summary>`)·push. push 거부 시 pull --rebase 후 재push
2. 모든 git 조작은 전달받은 repo(작업 트리) 안에서만. 전역 설정 변경 금지

## 승인 기준

- [ ] 픽스처에서 `reserve_number(..., "autofix", ...)` → `autofix-1.md`가 원격에
      존재, 내용은 정확히 두 줄
- [ ] 경합 재현: 클론 A가 예약·push 후, 같은 번호를 로컬에 만들어 둔 클론 B가
      reserve → B는 push 거부를 겪고 `autofix-2.md`로 성공한다 (원격에 1, 2 공존)
- [ ] archive에 `autofix-7.md`를 심어두면 next_number가 8을 반환
- [ ] `regression-tests/verify-autofix-3.sh`(빈 파일)를 심어두면 next_number ≥ 4
- [ ] finalize 후 원격 파일에 body가 포함된다

## 검증

`regression-tests/verify-issue-11.sh` 작성: 픽스처의 bare 원격 + 클론 2개로 위
시나리오 전부 자동화. 경합 재현 절차(의사코드):

1. 픽스처의 `origin.git`을 클론 A, B 두 개로 clone
2. A에서 `reserve_number(..., "autofix", ...)` → 원격에 `autofix-1.md` push됨
3. B는 fetch하지 않은 상태에서 `reserve_number` 호출 → B도 후보 1을 계산하지만
   push가 non-fast-forward로 거부됨 → 예약 커밋 제거 → pull --rebase →
   2 재계산 → `autofix-2.md` push 성공
4. 원격 `git ls-tree`에 `autofix-1.md`와 `autofix-2.md` 공존 확인

## 구현 결과

**구현 완료 일시**: 2026-07-10T18:27:59-0400

**변경 파일**:
- `.claude/skills/autoqafix/autoqafix_core.py` (수정: `next_number`,
  `reserve_number`, `finalize_item`, `_git` 헬퍼 추가)
- `regression-tests/lib/make-fixture-repo.sh` (버그 수정: 이 이슈의 경합
  테스트에서 처음으로 origin.git을 재클론하다가 발견됨 — 자세한 내용은 아래
  참고)
- `regression-tests/verify-issue-11.sh` (신규)

**계획 대비 편차**: 검증 과정에서 issue-3의 `make-fixture-repo.sh`에 잠재
버그를 발견해 함께 고쳤다 — bare `origin.git`을 `git init --bare`로 만든
직후 HEAD가 기본 브랜치(이 환경에서는 `master`)를 가리킨 채로 남아있었고,
이후 `work`에서 `git branch -M main` + `push`로 `main`만 만들어 origin에
올렸다. 지금까지의 이슈들은 전부 `work` 하나만 사용해 이 불일치가 드러나지
않았지만, issue-11의 경합 재현(클론 B가 origin을 새로 clone)이 처음으로
origin을 다시 clone하면서 "remote HEAD refers to nonexistent ref" 오류로
드러났다. `git init --bare -q -b main`으로 바꿔 HEAD가 처음부터 `main`을
가리키도록 고쳤다 — issue-3~10의 회귀 테스트 전부 재실행해 회귀 없음을
확인했다.

**검증 결과**: `regression-tests/verify-issue-11.sh` 단독 실행 exit
0(승인 기준 5개 시나리오 전부 PASS: 첫 예약 후 원격에 정확히 두 줄/경합
재현으로 autofix-2.md 성공 및 원격에 1·2 공존/archive 인식/verify 스크립트
인식/finalize 본문 반영). `run-regression-tests`로 issue-3~11 전체 실행
결과 PASS=9 FAIL=0. Python 프로젝트가 아니므로(저장소 루트에
`pyproject.toml` 없음) ruff/pyright/pytest 단계는 해당 없음.
