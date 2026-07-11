---
name: autofix
description: 트리거 `/autofix` — autoqafix 엔진의 fix 스트림을 1회 실행한다. smarthome 등 개별 repo의 autofix.bat(린트 스크립트)와 무관하다.
---

# /autofix — Claude Code 트리거

이 스킬은 얇은 트리거다 — 일하는 LLM은 스킬이 실행하는 스크립트 내부의 래퍼이지, 현재 세션이 아니다. 사용자가 `/autofix`를 입력하면 아래 절차만 따른다.

## 절차

1. **엔진 위치 해석** (아래 우선순위, 가장 먼저 찾은 것을 사용):
   - **자기 스킬 폴더의 형제 `../autoqafix/`** 디렉토리. 설치본(`~/.claude/skills/autofix`가 symlink)·클론(`/path/to/repo/.claude/skills/autofix`가 실제 폴더) 모두 성립한다.
   - **없으면** `~/git/autotdd` 클론이 있는지 확인한다 (즉, `~/git/autotdd/.claude/skills/autoqafix/`).
   - 그것도 없으면 사용자에게 "autoqafix 엔진 위치를 알려달라"고 질문하고 진행을 중단한다.

2. **cwd 검증**: 현재 작업 디렉토리(cwd)가 대상 앱 repo의 루트인지 확인한다. 판정 기준은 `.git/`이 cwd 바로 아래에 있는지다. 아니면 중단하고 `autofix 스킬은 대상 앱 repo 루트에서 실행해야 합니다 — cwd: <현재 경로>`라고 안내한다.

3. **엔진 실행**: `<엔진 폴더>/autofix.py --repo <cwd>`를 다음 형태로 실행한다
   (`--stream` 생략 시 기본값이 `autofix` 스트림이다; `autodev`는 같은
   스크립트를 `--stream issue`로 호출한다):

   ```
   uv -q run "<엔진 폴더>/autofix.py" --repo "$(pwd)"
   ```

4. **출력 요약 보고**: `autofix.py`의 실제 stdout은 아래 두 줄뿐이다 —
   이 값을 그대로 사용자에게 요약한다:
   - `처리: N건, 수동 분류: M건, 건너뜀: K건, 스탬프 추가: S건, 오류: E건`
   - `FIXED=<n>` — 실제로 archive까지 성공한 항목 수
   - 오류가 있었다면 stderr에 찍힌 개별 항목 오류 메시지도 함께 전달

## 금지

이 스킬은 issue 본문을 작성하거나 코드를 직접 고치는 일을 하지 않는다. fix 스트림은 `issues/autofix-#.md` 한 건을 처리해 archive로 보내는 것이지, 본 세션에서 코드를 만지지 않는다. archive 실패는 사람의 몫으로 남는다.

## 충돌 방지

이 `/autofix` 트리거는 smarthome 등 개별 repo에 들어 있는 `autofix.bat`(린트 스크립트)와 무관하다. 그쪽이 LLM 스크립트인지 단순 lint인지와 관계없이 본 스킬은 autoqafix 엔진만 호출한다.