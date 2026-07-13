# verify-issue-44 conflict with issue-47

issue-44 픽스처가 쓰던 `issue-N__TYPE-review-stats.json` 파일명과 `date`/
`derived` 필드가 issue-47에서 `issue-N__TYPE-agent-stats.json` / `started` /
`derived_by_reviewers`로 바뀌었다. `model` 필드 무시 계약과 전원 크레딧
규칙(SKILL.md 문구 검사)은 issue-44 결정 그대로이므로, 픽스처 파일명·
필드명만 갱신했다.
