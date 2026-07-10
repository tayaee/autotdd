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
