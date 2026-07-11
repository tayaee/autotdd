# issue-33: install.sh 견고화 — dangling symlink 감지·재연결 + set -e
agent-tier: paid-only

## 배경

issue-21 리뷰 종합 판정(`issue-21-feedback-review-by-fable.md` MF-4+GF-1,
원 지적: sonnet5 3.2, qwen36 3.2, gemini35 3.1.1).

- `install.sh`는 `[ -L "$dst" ]`(symlink 존재)만 확인하고 그 대상이 실제로
  resolve되는지 검사하지 않는다. repo가 이동/재클론되어 옛 경로를 가리키는
  깨진 링크가 남아 있어도 "이미 설치됨"으로 exit 0 성공 처리 — 사용자는
  `/autoqa` 등이 이유 없이 안 열리는 상황에 빠지고 install.sh 재실행으로도
  복구되지 않는다 (sonnet5가 직접 재현).
- `set -uo pipefail`만 있고 `set -e`가 없어 `mkdir -p`/`ln -s` 실패 시에도
  계속 진행해 잘못된 요약과 exit 0을 낼 수 있다.
- 두 결함 모두 "실패를 감지 못 하고 성공으로 보고"하는 동일 패턴이라 함께
  수정한다. 참고: 리뷰의 상대경로 symlink 제안은 기각됨(RJ-1 — repo 이동
  시 상대경로도 똑같이 깨짐; 본 이슈의 self-heal이 실 시나리오의 해법).

**선행**: 없음 — issue-32/34와 독립.

## 요구사항

1. symlink 분기 보강: `[ -L "$dst" ]`일 때 대상이 존재하는 경로로 resolve
   되는지 확인(`[ -e "$dst" ]` — symlink는 -e가 target 기준):
   - resolve됨 → 기존대로 "이미 설치됨" skip (idempotent 불변)
   - dangling → 링크를 제거하고 `$src`로 재연결, "재연결(깨진 링크 복구)"
     메시지 출력, installed 계수. 단 **일반 파일/디렉토리는 절대 삭제하지
     않음** — 삭제 대상은 `-L` 판정된 링크뿐
2. `set -euo pipefail`로 전환. 전환 후 스크립트 내 조건식·산술이 `-e`에
   걸리지 않는지 전 경로 확인 (`$((x + 1))` 대입은 안전, `((x++))` 금지)
3. 수정은 최소 diff — 3분기 구조(symlink/충돌/신규)와 요약 출력 형식 유지

## 승인 기준

- [ ] 깨진 symlink가 있는 상태에서 install.sh 실행 → 올바른 `$src`로 재연결
      되고 exit 0
- [ ] 재연결 직후 재실행 → "이미 설치됨" 4건, 상태 변화 없음 (idempotent)
- [ ] symlink가 아닌 파일/디렉토리 충돌은 기존대로 WARN + 건너뜀 (삭제 금지)
- [ ] `grep -n 'set -euo pipefail' install.sh` 매치 1건
- [ ] 기존 회귀 전체 PASS (verify-issue-21.sh의 1·2차 실행 시나리오 포함)

## 검증

`regression-tests/verify-issue-33.sh` 작성: verify-issue-21.sh와 동일한
fake HOME(`mktemp -d` + `HOME` 오버라이드) 격리 패턴으로 —
① 정상 설치 후 링크 4개를 존재하지 않는 경로로 바꿔치기 → install.sh 재실행
→ 4개 모두 `$src`로 재연결됐는지 `readlink` 대조,
② 일반 디렉토리를 심어두고 실행 → 그대로 보존 + WARN 확인,
③ 연속 2회 실행 exit 0 동일 확인.

## 구현 결과

* **구현 완료 일시**: 2026-07-11T19:05:00-04:00
* **변경 파일**:
  * `install.sh` (`set -uo pipefail` → `set -euo pipefail` 전환; symlink 분기를 `[ -L "$dst" ]` 안에서 `[ -e "$dst" ]`로 재분기 — resolve되면 기존대로 "이미 설치됨" skip, dangling이면 `rm -f "$dst"` 후 `ln -s "$src" "$dst"` 재연결 + "재연결(깨진 링크 복구)" 메시지 출력 + `installed` 계수 증가. 삭제 대상은 `-L` 판정된 링크뿐 — 일반 파일/디렉토리 분기는 그대로 보존)
  * `regression-tests/verify-issue-33.sh` (신규 — set -euo pipefail 존재, 깨진 symlink 4개 자동 재연결(대상 경로 대조 포함), 재연결 메시지 출력, 재연결 후 재실행 idempotent(이미 설치됨 4건 + 상태 불변), 일반 디렉토리 충돌 시 WARN+보존, 연속 2회 실행 exit code 동일 = 15개 검증)
* **계획 대비 변경 사항**: 없음 (요구사항 1~3 그대로 수행). 검토한 리뷰의 상대경로 symlink 제안(RJ-1)은 issue 본문 배경대로 기각 유지 — 절대경로 self-heal이 실 시나리오(repo 이동/재클론)의 해법.
* **검증 결과**:
  * `verify-issue-33.sh` PASS — 15개 검증 모두 통과
  * `verify-issue-21.sh` PASS — install.sh 1·2차 실행 시나리오 포함 회귀 무손상
  * `python3 -m py_compile` 대상 없음 (본 이슈는 install.sh/셸 스크립트만 변경)
  * repo 루트에 `pyproject.toml` 없어 ruff/pyright/pytest 단계는 tdd2 규칙대로 생략
  * 전체 회귀 테스트: 기존 27개(issue-32 포함) + 신규 `verify-issue-33.sh` = 28개 전부 PASS
