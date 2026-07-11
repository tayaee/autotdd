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

3. **엔진 실행**: `<엔진 폴더>/autofix.py --repo <cwd>`를 다음 형태로 실행한다:

   ```
   uv -q run "<엔진 폴더>/autofix.py" --repo "$(pwd)"
   ```

4. **출력 요약 보고**: 결과를 사용자에게 요약한다. 특히 다음 토큰을 명시한다:
   - `[원인] ...` — 결함 원인
   - `[조치] ...` — 권장 조치
   - `FIXED=<n>` 또는 `FIXED=` (없음) — 처리된 항목 수
   - `FAIL <항목>` 줄이 있으면 그 항목을 모두 나열
   - `OK <항목>` 요약

## 금지

이 스킬은 issue 본문을 작성하거나 코드를 직접 고치는 일을 하지 않는다. fix 스트림은 `issues/autofix-#.md` 한 건을 처리해 archive로 보내는 것이지, 본 세션에서 코드를 만지지 않는다. archive 실패는 사람의 몫으로 남는다.

## 충돌 방지

이 `/autofix` 트리거는 smarthome 등 개별 repo에 들어 있는 `autofix.bat`(린트 스크립트)와 무관하다. 그쪽이 LLM 스크립트인지 단순 lint인지와 관계없이 본 스킬은 autoqafix 엔진만 호출한다.