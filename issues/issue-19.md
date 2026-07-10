# issue-19: tdd2/autotdd/acpd 스킬의 두 스트림·접미사 인식

## 배경

세 스킬의 실체는 이 repo의 `.claude/skills/{tdd2,autotdd,acpd}/`에 있다(사용자
머신에는 `~/.claude/skills/`로 설치/symlink됨). 현재 `issues/issue-*.md` glob이라서
① `autofix-#` 스트림을 모르고, ② `issue-3-later.md` 같은 접미사 파일까지 잡는다.

## 요구사항

1. 세 SKILL.md(및 스킬 디렉토리 안의 보조 스크립트가 있으면 그것도)에서 작업
   항목 참조를 다음 규약으로 일반화:
   - 항목 id는 `issue-<N>` 또는 `autofix-<N>` 두 형태. 숫자만 받던 곳은
     `<stream>-<N>` 전체 id도 받도록 문구 수정 (숫자만 오면 기존대로 issue 스트림)
   - 열거 glob은 접미사 파일 제외: `issue-#-later.md`, `issue-#-manual.md`,
     `issue-#-agent-failed.md`(autofix도 동일)는 "남은 이슈" 목록에서 제외한다는
     지시를 명시. 판별 규칙: 파일명이 `<stream>-<숫자>.md`와 정확히 일치하는
     것만 대상
   - tdd2의 회귀 스크립트 명명: `regression-tests/verify-<stream>-<N>.sh`
   - acpd의 commit 접두사: `<stream>-<N>:` (기존 `issue-N:`의 일반화),
     archive 이동 대상도 두 스트림 모두
2. 수정은 최소 diff로 — 각 파일에서 바뀐 줄 수를 결과 보고에 명시
3. git 추적 파일이므로 별도 백업은 만들지 않는다 (rollback은 git으로)

## 승인 기준

- [ ] 세 SKILL.md에 `autofix-` 문자열이 등장한다 (일반화 반영 증거)
- [ ] 세 SKILL.md에 접미사 제외 규칙(`-later` 언급)이 등장한다
- [ ] tdd2 SKILL.md의 verify 스크립트 경로가 `verify-<stream>` 형태를 안내한다

## 검증

`regression-tests/verify-issue-19.sh` 작성: 위 grep 검사들 (파일 경로는 repo
상대 `.claude/skills/...` 기준).
