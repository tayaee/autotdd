# verify-issue-22 ↔ issue-39 충돌 기록

issue-39(파일명 규약 v2)가 파킹 접미사(`-later`/`-manual`/`-agent-failed`)와
리뷰 산출물 명명을 대문자 태그 문법(`__STATE-*`/`__TYPE-*`/`__BY-*`)으로
전면 교체했다 (정본: docs/spec/spec-issue-filenames.md).

이에 따라 verify-issue-22.sh의 구 규약 단언을 신규약으로 갱신했다
(의도된 동작 변경 — 규약 v1 단언은 폐기). 원 이슈의 검증 의도(동작
자체)는 그대로 유지되며 파일명 표기만 바뀌었다. 사람 확인 후 이 노트는
삭제해도 된다.
