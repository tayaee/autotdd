# Conflict: issue-45 vs issue-46

이슈 46의 설계 변경에 의해 이슈 45의 `log-run.sh` 래퍼 스크립트와 `coder-stats.jsonl` 수집 및 아카이브 방식이 완전히 폐기되었습니다.
대신 `coding-stats.json` 단일 통합 파일 스키마가 도입되었으며, 이에 따라 `verify-issue-45.sh` 회귀 테스트 스크립트가 무효화되어 바이패스 처리되었습니다.
상세한 변경 내역은 `issues/issue-46.md`를 참고하시기 바랍니다.
