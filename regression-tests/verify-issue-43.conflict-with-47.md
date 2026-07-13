# verify-issue-43 conflict with issue-47

issue-43이 세운 스코어보드 CLI 픽스처가 쓰던 `issue-N__TYPE-review-stats.json`
파일명과 최상위 `date`/`derived` 필드가 issue-47에서 각각
`issue-N__TYPE-agent-stats.json` / `started` / `derived_by_reviewers`로
바뀌었다. CLI의 집계 로직·승격률 계산·손상 파일 내성 등 issue-43의
핵심 검증 대상은 변하지 않았으므로, 픽스처 파일명·필드명만 갱신하고
스크립트는 유지했다.
