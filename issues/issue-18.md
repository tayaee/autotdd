# issue-18: Claude Code 트리거 스킬 4종

## 배경

사용방식 1: Claude Code 세션(cwd = 대상 앱 repo)에서 `/autoqa` `/autofix`
`/autodev` `/autoqafix`로 1회형을 실행한다. 스킬은 얇은 트리거다 — 일하는 LLM은
스킬이 실행하는 스크립트 내부의 래퍼이지, 현재 세션이 아니다.

## 요구사항

1. repo의 `.claude/skills/{autoqa,autofix,autodev}/SKILL.md` 3개와 엔진 폴더의
   `.claude/skills/autoqafix/SKILL.md`(트리거 `/autoqafix` 겸용) 작성 — 스킬
   폴더가 원본이고 `~/.claude/skills/`에는 설치(symlink)된다
2. 각 SKILL.md: frontmatter(name, description — 트리거 문구 `/autoqa` 등 명시) +
   본문 지시: ① 엔진 위치 해석 — 자기 스킬 폴더의 형제 `../autoqafix/`(설치본·
   클론 모두 성립), 없으면 `~/git/autotdd` 클론, 그것도 없으면 사용자에게 질문,
   ② cwd가 대상 앱 repo 루트인지 확인(아니면 중단하고 안내),
   ③ `uv -q run <엔진 폴더>/auto<role>.py --repo <cwd>` 실행, ④ 출력(특히
   `[원인]`/`[조치]`, `FIXED=`)을 사용자에게 요약 보고. 스킬 자신이 issue 본문을
   쓰거나 코드를 고치는 것을 금지한다는 문장 포함
3. 기존 스킬과의 충돌 방지: description에 "smarthome 등 개별 repo의 autofix.bat
   (린트 스크립트)와 무관"임을 명시
4. repo 루트에 `install.sh` 신설: `.claude/skills/{autoqa,autofix,autodev,
   autoqafix}` 4개를 `~/.claude/skills/`로 symlink 설치
   (이미 존재하면 건너뜀, idempotent)

## 승인 기준

- [ ] repo에 4개 SKILL.md가 존재하고 frontmatter가 유효하다
      (`---`로 열고 닫으며 name/description 포함)
- [ ] `install.sh`를 2회 실행해도 에러 없이 같은 상태 (idempotent)
- [ ] 설치 후 `~/.claude/skills/<이름>` 4개가 repo 폴더를 가리킨다 (symlink)

## 검증

`regression-tests/verify-issue-18.sh` 작성: 위 전부. HOME을 임시 디렉토리로
바꿔 install.sh의 symlink 동작을 검증(실 HOME 오염 금지).
