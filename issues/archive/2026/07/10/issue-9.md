# issue-9: select-llm.py — LLM 선정기
agent-tier: paid-only

## 배경

유효 잔여율 규칙(CONTEXT.md "유효 잔여율")의 단일 구현. 모든 도구가 이것만 호출한다.

## 요구사항

1. `.claude/skills/autoqafix/select-llm.py` 작성 (PEP-723, `uv -q run`)
2. 후보는 env `AUTOQAFIX_WRAPPERS`(`"<래퍼명>:paid|local,..."` — 나열 순서가
   우선순위, 기본 `claudecli:paid,minimaxcli:paid,qwencli:local`)로 구성.
   래퍼별 usage 스크립트를 subprocess로 실행해 JSON 파싱. 명령은 env로 대체 가능:
   `AUTOQAFIX_USAGE_CMD_<래퍼명 대문자>` (기본: `uv -q run
   .claude/skills/autoqafix/usage-<래퍼명>.py`, autotdd repo 루트 기준 절대경로로
   해석). usage 스크립트가 없는 래퍼는 후보 제외 + stderr 경고
3. 선정 규칙 (docs/autoqafix-design.md "LLM 선정"):
   - 적격 유료 = `available && effective_remaining_pct >= 50`
   - 적격이 여럿 → effective 큰 쪽, 동률 → 목록 앞쪽
   - 유료 부적격 → 로컬(local) 중 `available` 첫 번째
   - 전부 불가 → stdout에 `none`, exit 2
4. stdout 한 줄: 선정된 래퍼 이름(`claudecli` | `minimaxcli` | `qwencli` | ...)
   또는 `none`. exit 0 (none만 2)
5. `--explain` 플래그: stderr에 후보 전부의 수치와 판정 근거를 표로 출력
6. env `AUTOQAFIX_WRAPPER`가 설정돼 있으면 usage 조회 없이 그 값을 그대로 출력
   (강제 지정·테스트 주입점)

## 승인 기준

다음 매트릭스를 픽스처(USAGE_FIXTURE 파일들 + AUTOQAFIX_USAGE_CMD_*=cat류)로 검증:

- [ ] claudecli(5h 80, 주간 60 → 유효 60) vs minimaxcli(5h 70, 주간 90 → 유효 70)
      → 유효 잔여율이 큰 `minimaxcli`
- [ ] claudecli(90, 40) vs minimaxcli(45, 80) → 둘 다 유효 <50 → qwen UP →
      `qwencli`
- [ ] 둘 다 유효 55로 동률 → 목록 앞쪽인 `claudecli`
- [ ] 전부 불가 → `none` + exit 2
- [ ] `AUTOQAFIX_WRAPPER=qwencli` → usage 명령 실행 없이 `qwencli`

## 검증

`regression-tests/verify-issue-9.sh` 작성: 위 매트릭스 전부. 각 케이스의 기대값을
스크립트 주석에 계산 근거와 함께 남길 것.

## 구현 결과

**구현 완료 일시**: 2026-07-10T18:12:33-0400

**변경 파일**:
- `.claude/skills/autoqafix/select-llm.py` (신규)
- `regression-tests/verify-issue-9.sh` (신규)

**계획 대비 편차**: 없음. `AUTOQAFIX_USAGE_CMD_<이름 대문자>` 오버라이드가
있으면 usage 스크립트 존재 여부를 확인하지 않고 그 커맨드를 바로 사용하도록
했다(요구사항 2의 "usage 스크립트가 없는 래퍼는 후보 제외"는 기본 경로 —
`uv -q run usage-<이름>.py` — 에만 적용하는 것으로 해석). 동률 처리는 Python
`max()`가 처음 발견한 최댓값을 유지하는 특성을 그대로 활용해
"동률 → 목록 앞쪽" 요구사항을 별도 로직 없이 충족시켰다.

**검증 결과**: `regression-tests/verify-issue-9.sh` 단독 실행 exit 0(승인
기준 매트릭스 5개 케이스 + `--explain` 보너스 케이스 모두 PASS, `uv -q run`
+ `AUTOQAFIX_USAGE_CMD_*=cat <픽스처>`로 실제 fixture 검증). 케이스 5에서는
usage 커맨드를 실행하면 즉시 실패할 존재하지 않는 경로를 지정해 두어
"usage 조회 없이" 요구사항이 실제로 지켜지는지까지 확인했다.
`run-regression-tests`로 issue-3~9 전체 실행 결과 PASS=7 FAIL=0. Python
프로젝트가 아니므로(저장소 루트에 `pyproject.toml` 없음) ruff/pyright/pytest
단계는 해당 없음 — `select-llm.py`는 PEP-723 인라인 메타데이터로 `uv -q run`
독립 실행됨을 직접 확인했다.
