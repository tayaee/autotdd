# verify-issue-41 conflict with issue-47

issue-41이 못박은 산출물 파일명 `issue-N__TYPE-review-stats.json`이
issue-47에서 `issue-N__TYPE-agent-stats.json`(coding-stats.json과 통합)으로
바뀌었다. `reviewers` 서브트리의 필드 의미(findings/gate_rejected/
verify_rejected/must_fix/good_to_fix)는 issue-41 결정 그대로이므로,
스크립트를 폐기하지 않고 파일명 리터럴 검사만 갱신했다.
