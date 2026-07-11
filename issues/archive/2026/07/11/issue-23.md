# issue-23: 설치·운영 문서 (SETUP-autoqafix.md)
agent-tier: paid-only

## 배경

사람이 새 머신/새 repo에 스위트를 배치할 때 따라 하는 단일 문서. 마지막 이슈 —
issue-3 ~ issue-22가 모두 archive된 뒤 작성한다.

## 요구사항

1. `docs/SETUP-autoqafix.md` 작성. 섹션:
   - **사전 준비**: uv 설치, 사용할 래퍼가 감싸는 CLI(`claude`/`qwen` 등)를
     PATH에, git identity, autotdd 클론 위치(또는 스킬 설치 + `install.sh`)
   - **점검 순서**: ① `autoqafix-doctor.{sh,bat}` (대상 repo에서), ② 실 LLM 확인은
     `ping-claudecli.*` 등 사용하는 래퍼 것만 (크레딧 소모 주의 문구), ③ 픽스처 기반 전체 회귀:
     `for f in regression-tests/verify-*.sh; do bash "$f" || echo "FAIL $f"; done`
   - **Windows production 배치**: `shell:startup`에 지름길 생성, 대상 =
     `<autotdd>\autoqafix-loop.bat --reboot-on-fix`, **"시작 위치" = 대상 앱 repo**
     (이 설정이 cwd 규약의 전부임을 강조), 재시동 폭주 가드 설명
   - **WSL 수동 사용**: 대상 repo에서 `<autotdd>/autoqa.sh`, `autofix.sh` 직접 실행
   - **Claude Code 스킬**: `/autoqa` 등 4종 사용법
   - **운영 규약 요약**: 스트림 2개, 상태 접미사 4종과 사람의 대응(-manual은 직접
     처리, -agent-failed는 실패 기록 읽고 보강 후 접미사 제거, 정체 시 개입),
     `CONTEXT.md`·`docs/autoqafix-design.md` 링크
   - **알려진 정리 작업**: `smarthome-project/autofix.bat`(린트 스크립트)은 이름
     충돌이므로 `lint.bat`으로 개명 권고 (해당 repo에서 사람이 수행)
2. 명령은 전부 복사-실행 가능한 코드블록으로

## 승인 기준

- [ ] 문서가 존재하고 위 7개 섹션 제목이 모두 있다
- [ ] 문서 안의 모든 파일 경로가 실재한다 (스크립트로 추출·검사)
- [ ] "시작 위치" 설정 설명이 포함된다

## 검증

`regression-tests/verify-issue-23.sh` 작성: 섹션 존재 + 경로 실재 검사.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T20:55:00+0000
- **변경 파일**:
  - `docs/SETUP-autoqafix.md` (신규) — 7개 섹션(사전 준비 / 점검 순서 /
    Windows production 배치 / WSL 수동 사용 / Claude Code 스킬 / 운영 규약
    요약 / 알려진 정리 작업)으로 구성. 모든 명령은 복사-실행 가능한 코드블록.
  - `regression-tests/verify-issue-23.sh` (신규) — 9개 section/marker assertion
    + 11개 `<autotdd>/...` 경로 실재 검사 = 20 PASS.
- **계획과 차이**:
  - 원안의 `<autotdd>\autoqafix-loop.bat --reboot-on-fix`는 실재하지 않는 파일
    (현재 `<autotdd>` 루트에는 `autodev-loop.{bat,sh,ps1}`, `autofix-loop.{bat,sh,ps1}`,
    `autoqa-loop.{bat,sh,ps1}` 만 존재 — `role-loop.py --role {qa,fix,dev}` 디스패처).
    본 문서는 이를 충실히 반영해 "역할별로 다름" 명시 후 3개 loop.bat 모두
    예시로 인용. 추후 `autoqafix-loop.{bat,sh,ps1}` 파일이 별도 이슈로
    신설되면 본 문서를 갱신할 것.
  - `<autotdd>` 표기는 autotdd 클론 위치(권장 `~/git/autotdd`)를 가리키는
    플레이스홀더. 사용자가 실제 경로로 치환해 읽는다.
- **검증 결과**: verify-issue-23.sh 20 PASS / 0 FAIL. 전체 회귀 32/32 rc=0.
  모든 11개 `<autotdd>/...` 경로 실재 확인 (autoqafix-doctor.sh, autoqa.sh,
  autofix.sh, autodev.sh, autodev-loop.sh, autofix-loop.sh, install.sh,
  CONTEXT.md, docs/autoqafix-design.md, wrappers/ping-claudecli.sh,
  wrappers/ping-qwencli.sh).
