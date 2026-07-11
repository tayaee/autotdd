# issue-32: 트리거 스킬 SKILL.md ↔ 엔진 계약 정합화 (/autodev 동작 불능 수정)
agent-tier: paid-only

## 배경

issue-21 리뷰 종합 판정(`issue-21-feedback-review-by-fable.md` MF-1+MF-2+MF-3,
원 지적: sonnet5 2.1/2.2/3.1, qwen36 2.1/2.2/3.1).

- `autodev/SKILL.md`가 존재하지 않는 `<엔진 폴더>/autodev.py`를 실행하라고
  지시한다 — `/autodev` 트리거가 **항상 즉시 실패**한다. 실제 dev 스트림
  진입점은 `autofix.py --stream issue`다(레거시 `autodev.sh`와 autofix.py
  docstring이 명시).
- `autoqa`/`autofix`/`autodev` 3개 SKILL.md의 4단계 "출력 요약 보고" 토큰
  계약(`[원인]`/`[조치]`/`FIXED=`/`FAIL`/`OK`)은 `autoqafix-doctor.py` 고유
  출력의 복붙이라 실제 엔진 stdout과 불일치한다. 실측:
  - `autoqa.py`(+`error-to-autofix.py`): 해당 토큰 stdout 출력 **0건** —
    stderr 메시지와 exit code(0 정상 / 1 preflight 실패 / 3 락 선점)뿐
  - `autofix.py`: `처리: N건, 수동 분류: M건, 건너뜀: K건, 스탬프 추가: S건,
    오류: E건` 1줄 + `FIXED=<n>` 1줄뿐
  - `autoqafix`(doctor)만 문서와 일치 — 수정 대상 아님
- verify-issue-21.sh는 문구 존재만 검사하고 SKILL.md가 참조하는 엔진
  스크립트의 실존을 검증하지 않아 위 결함이 13 PASS로 병합됐다
  (issue-16/issue-20의 "빈 검사" 교훈 재발).

**선행**: 없음 — 즉시 착수 가능. issue-33/34와 독립.

## 요구사항

1. `.claude/skills/autodev/SKILL.md`의 3단계(엔진 실행)를
   `uv -q run "<엔진 폴더>/autofix.py" --repo "$(pwd)" --stream issue`로
   수정하고, `autofix`/`autodev`가 동일 파일(`autofix.py`)을 스트림만 다르게
   호출한다는 점을 두 SKILL.md에 상호 참조로 명시
2. 3개 SKILL.md(`autoqa`/`autofix`/`autodev`)의 4단계 출력 계약을 실제
   stdout에 맞게 재작성:
   - `autofix`/`autodev`: `처리: N건, …` 요약 줄 + `FIXED=<n>` 기준으로 보고
   - `autoqa`: stdout 무출력이 정상 — exit code(0/1/3)와 stderr, 그리고
     생성물(`issues/autofix-#.md` 신규 파일 유무) 기준으로 보고하도록 안내
   - `autoqafix/SKILL.md`는 불변 (doctor 계약과 이미 일치)
3. `regression-tests/verify-issue-32.sh` 신설 — 이 유형의 구조적 잠금:
   - 4개 SKILL.md 본문이 참조하는 `*.py` 엔진 스크립트 경로를 추출해
     `.claude/skills/autoqafix/`에 실제 파일이 존재하는지 대조
   - 각 SKILL.md의 출력 계약 토큰이 해당 엔진 스크립트의 print 실측과
     모순되지 않는지 grep 대조(최소: `autoqa` 문서에 doctor 토큰 부재,
     `autodev` 문서에 `--stream issue` 존재, `autodev.py` 문자열 부재)
4. 수정은 최소 diff — SKILL.md의 다른 절(엔진 위치 해석, cwd 검증, 금지,
   충돌 방지)은 불변

## 승인 기준

- [ ] `grep -rn 'autodev\.py' .claude/skills/` 매치 0건
- [ ] `autodev/SKILL.md`에 `autofix.py`와 `--stream issue`가 등장
- [ ] `autoqa/SKILL.md`에 `[원인]`/`[조치]`/`OK ` 토큰 지시가 없음
- [ ] `verify-issue-32.sh`가 엔진 경로 실존 검사를 포함하고 PASS
- [ ] 기존 회귀 전체 PASS (verify-issue-21.sh 포함)

## 검증

`regression-tests/verify-issue-32.sh` 작성(요구사항 3). 추가로 수동 스모크:
대상 repo에서 `uv -q run .claude/skills/autoqafix/autofix.py --repo "$(pwd)"
--stream issue --help` 상당의 호출이 "파일 없음"으로 죽지 않는지 확인.

## 구현 결과

* **구현 완료 일시**: 2026-07-11T18:40:00-04:00
* **변경 파일**:
  * `.claude/skills/autodev/SKILL.md` (3단계를 `autofix.py --repo "$(pwd)" --stream issue`로 교체, 실존하지 않는 `autodev.py` 참조 제거, `autofix`와 같은 엔진 스크립트를 스트림만 다르게 호출한다는 상호 참조 추가, 4단계 출력 계약을 실측 stdout — `처리: N건, ...` 1줄 + `FIXED=<n>` 1줄 — 로 재작성)
  * `.claude/skills/autofix/SKILL.md` (3단계에 `--stream` 기본값이 `autofix`이고 `autodev`가 같은 스크립트를 `--stream issue`로 호출한다는 상호 참조 추가, 4단계 출력 계약을 실측 stdout으로 재작성)
  * `.claude/skills/autoqa/SKILL.md` (4단계를 doctor 전용 토큰 복붙에서 실제 계약 — 성공 시 stdout 무출력, exit 0/1/3과 `issues/autofix-#.md` 신규 파일 유무로 판단 — 으로 재작성)
  * `.claude/skills/autoqafix/SKILL.md` (불변 — doctor 계약과 이미 일치, 요구사항 2 명시대로 손대지 않음)
  * `regression-tests/verify-issue-32.sh` (신규 — `autodev.py` 문자열 부재, autodev 문서의 `autofix.py`+`--stream issue` 등장, autoqa 문서의 doctor 토큰 부재, autofix/autodev 문서의 실측 계약 반영, autoqafix 문서 불변, 4개 SKILL.md가 참조하는 `*.py` 엔진 스크립트 실존 대조 = 11개 검증)
* **계획 대비 변경 사항**: 없음 (요구사항 1~4 그대로 수행)
* **검증 결과**:
  * `verify-issue-32.sh` PASS — 11개 검증 모두 통과
  * 수동 스모크: `uv -q run autofix.py --repo <fixture> --stream issue --help` — `--stream {autofix,issue}` 옵션 정상 인식, exit 0, "파일 없음" 오류 없음
  * `python3 -m py_compile` 대상 없음 (본 이슈는 SKILL.md 문서만 변경, `.py` 파일 무변경)
  * repo 루트에 `pyproject.toml` 없어 ruff/pyright/pytest 단계는 tdd2 규칙대로 생략
  * 전체 회귀 테스트: 기존 26개 `verify-issue-*.sh` + 신규 `verify-issue-32.sh` = 27개 전부 PASS
