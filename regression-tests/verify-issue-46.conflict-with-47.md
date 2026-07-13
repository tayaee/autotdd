# verify-issue-46 conflict with issue-47

issue-46이 정의한 `issue-N__TYPE-coding-stats.json`이 issue-47에서
review-stats.json과 통합되어 `issue-N__TYPE-agent-stats.json`이 되었다.
`coders` 서브트리 필드 의미(mvp/review_outcome/static_analysis_failures/
defect 밀도 계산식)는 issue-46 결정 그대로이므로, SKILL.md 문자열 검사와
픽스처 파일명만 `coding-stats.json` → `agent-stats.json`으로 갱신하고
스크립트는 유지했다.
