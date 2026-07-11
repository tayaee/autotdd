# issue-26: run_pings 크로스 플랫폼 — ping 3종 확장자 + OS별 인터프리터
agent-tier: paid-only

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` M5,
원 지적: gemini ③). doctor의 `run_pings`가 `["bash", str(ping)]`을
하드코딩하고 `ping-<name>.sh`만 탐색한다. 스킬의 `wrappers/`에는
`ping-*.bat`·`ping-*.ps1`이 전 래퍼에 이미 존재하는데 미사용 —
네이티브 Windows(WSL 미사용)에서 `--ping` 실행 시 bash 부재로
`FileNotFoundError` 크래시. `.bat`/`.ps1` 런처를 제공하는 도구가
내부 구현에서 Windows를 못 돌게 만든 상태.

## 요구사항

1. ping 스크립트 탐색을 `ping-<name>.{sh,ps1,bat}` 3종으로 확장 —
   탐색 순서는 플랫폼 우선(POSIX: `.sh` 우선, Windows: `.bat`/`.ps1` 우선),
   기존과 동일하게 `AUTOQAFIX_WRAPPER_DIR` 먼저, 없으면 스킬 `wrappers/` 폴백
2. 실행 인터프리터를 확장자별로 선택: `.sh` → `bash`, `.bat` → `cmd /c`,
   `.ps1` → `powershell -ExecutionPolicy Bypass -File`
3. 인터프리터 부재 등 실행 실패는 크래시 대신 `FAIL ping-<name>` +
   `[원인]`/`[조치]`로 처리
4. Linux/WSL에서의 기존 동작(`.sh` ping)은 불변

## 승인 기준

- [ ] Linux에서 기존 `--ping` 경로 회귀 없음 (verify-issue-20.sh TEST 7 PASS)
- [ ] `.sh` 부재 + `.ps1`/`.bat`만 존재 시 크래시 없이 정의된 동작
      (실행 가능하면 실행, 불가하면 FAIL + 조치 안내)
- [ ] ping 파일이 전혀 없으면 기존대로 `FAIL ping-<name>` (경로 표기)
- [ ] 기존 회귀 전체 PASS

## 검증

`regression-tests/verify-issue-26.sh` 작성: Linux에서 검증 가능한 범위 —
① `.sh` ping 정상 경로, ② `.sh` 제거 + `.bat`만 존재 시 크래시 없음(FAIL
또는 실행), ③ ping 전무 시 FAIL. Windows 실동작은 CI 범위 밖임을 주석으로
명시 (run_with_timeout의 기존 관례와 동일).

## 구현 결과

- **구현 완료 일시**: 2026-07-11T12:53:00-04:00
- **변경 파일**: `.claude/skills/autoqafix/autoqafix-doctor.py`, `regression-tests/verify-issue-26.sh`
- **계획과 차이**: 없음
- **검증 결과**: verify-issue-26.sh PASS. 전체 회귀 테스트 통과.
