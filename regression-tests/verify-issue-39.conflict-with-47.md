# verify-issue-39 conflict with issue-47

issue-39가 spec-issue-filenames.md에 못박은 예시 줄 `issue-N__TYPE-review-stats.json`이
issue-47(review-stats.json + coding-stats.json → agent-stats.json 통합)로
`issue-N__TYPE-agent-stats.json`으로 교체되었다. issue-39의 원래 의도
("`.md` 외 확장자 산출물도 태그 문법을 쓴다"는 것을 spec이 예시로
보여준다)는 그대로 유지되므로, 스크립트를 폐기하지 않고 검사 패턴만
`review-stats` → `agent-stats`로 갱신했다.
