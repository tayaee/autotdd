# issue-24: lock 견고화 — peek_lock/is_lock_reclaimable 공용 API + lock 검증 시나리오
agent-tier: paid-only

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` M1+M2+M3,
원 지적: qwen P0-1, minimax P0-1/P0-2/P1-1/P1-2/P2-2, gemini ④)의 P0 묶음.

- `autoqafix-doctor.py`의 `check_lock`이 비정상 잠금 파일에서 크래시:
  `pid=abc` 같은 값이면 `int()` ValueError, 잠금 경로가 디렉터리면
  `_read_lock`의 `read_text()`가 IsADirectoryError. 두 경우 모두 traceback
  후 **exit 0으로 정상 종료를 가장**한다(진단 완료 푸터 미출력).
  `autoqafix_core.acquire_lock`도 동일한 pid 파싱 버그를 공유한다.
- stale 판정 정책 drift: `acquire_lock`은 `pid_dead ∨ is_stale`
  (`AUTOQAFIX_LOCK_STALE_SEC`, 기본 4h) 이중 조건으로 회수하는데, doctor의
  `check_lock`은 `pid_dead`만 봐서 회수 가능한 잠금을 FAIL로 오진하고
  "잠금 삭제"를 유도한다.
- `verify-issue-20.sh`는 잠금 파일을 만드는 테스트가 0개 — 위 P0의 회귀를
  잡을 수 없다 (표면 15/15 PASS가 빈 검사를 가장).
- doctor/`autoqa.py`/`autofix.py`가 사설 API `core._lock_path`/`core._read_lock`을
  직접 호출한다.

## 요구사항

1. `autoqafix_core.py`에 public API 추출:
   - `peek_lock(repo) -> dict | None` — 잠금 부재 시 None. 읽기 실패
     (디렉터리, 권한 등 OSError)와 필드 비정상(pid가 정수 아님 등)은
     예외를 전파하지 않고 정의된 값으로 처리 (호출자가 "비정상 잠금"을
     구분할 수 있어야 함 — 형태는 구현 시 결정하되 docstring에 계약 명시)
   - `is_lock_reclaimable(...) -> bool` (또는 사유 포함 반환) —
     `pid_dead ∨ is_stale` 판정을 `acquire_lock`과 **단일 소스**로 공유.
     `AUTOQAFIX_LOCK_STALE_SEC` 반영
2. `acquire_lock`이 위 API를 사용하도록 리팩토링 — 비정상 pid/디렉터리
   잠금에서도 크래시 없이 회수 또는 거부를 판정 (기존 잠복 버그 함께 해소)
3. doctor `check_lock` 재작성:
   - 잠금 없음 → OK
   - 회수 가능(소유 pid 사망 또는 stale 초과) → OK (사유 표기)
   - 비정상 잠금(파싱 불가/디렉터리) → 크래시 없이 FAIL + `[원인]`/`[조치]`
   - 진짜 살아있는 잠금만 기존 FAIL 메시지 유지
4. doctor/`autoqa.py`/`autofix.py`의 `core._lock_path`/`core._read_lock` 직접
   호출을 public API로 교체
5. `autoqafix_core.py --selftest`에 peek_lock/is_lock_reclaimable 케이스 추가

## 승인 기준

- [ ] `pid=abc` 잠금 파일에서 doctor가 크래시 없이 진단 완료, exit = FAIL 수
- [ ] 잠금 경로가 디렉터리여도 동일 (traceback 없음, 진단 완료 푸터 출력)
- [ ] 다른 호스트 + start가 `AUTOQAFIX_LOCK_STALE_SEC` 초과 → OK (stale, 회수 가능)
- [ ] 다른 호스트 + start가 4h 이내 → FAIL 유지
- [ ] 동일 호스트 + 살아있는 pid → FAIL 유지
- [ ] `acquire_lock`이 `pid=abc` 잠금을 크래시 없이 회수
- [ ] doctor/autoqa/autofix에 `_lock_path`/`_read_lock` 직접 호출 0건
- [ ] 기존 회귀 전체 PASS (verify-issue-10 ~ 20 포함)

## 검증

`regression-tests/verify-issue-24.sh` 작성: 잠금 시나리오 최소 7종
(없음 / 동일 호스트 alive / 동일 호스트 dead / 다른 호스트 fresh /
다른 호스트 stale / 비정상 pid / 디렉터리 / 빈 파일) + core --selftest.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T12:51:00-04:00
- **변경 파일**: `.claude/skills/autoqafix/autoqafix_core.py`, `.claude/skills/autoqafix/autoqafix-doctor.py`, `.claude/skills/autoqafix/autoqa.py`, `.claude/skills/autoqafix/autofix.py`, `regression-tests/verify-issue-24.sh`
- **계획과 차이**: 없음
- **검증 결과**: verify-issue-24.sh PASS. 전체 회귀 테스트 통과.
