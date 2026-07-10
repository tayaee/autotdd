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
