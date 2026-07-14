---
name: autoqa
description: 트리거 `/autoqa` — autoqafix 엔진의 qa 스트림을 1회 실행한다. smarthome 등 개별 repo의 autofix.bat(린트 스크립트)와 무관하다.
---

# /autoqa — Claude Code 트리거

이 스킬은 얇은 트리거다 — 일하는 LLM은 스킬이 실행하는 스크립트 내부의 래퍼이지, 현재 세션이 아니다. 사용자가 `/autoqa`를 입력하면 아래 절차만 따른다.

## 절차

1. **엔진 위치 해석** (아래 우선순위, 가장 먼저 찾은 것을 사용):
   - **자기 스킬 폴더의 형제 `../autoqafix/`** 디렉토리. 설치본(`~/.claude/skills/autoqa`가 symlink)·클론(`/path/to/repo/.claude/skills/autoqa`가 실제 폴더) 모두 성립한다.
   - **없으면** `~/git/autotdd` 클론이 있는지 확인한다 (즉, `~/git/autotdd/.claude/skills/autoqafix/`).
   - 그것도 없으면 사용자에게 "autoqafix 엔진 위치를 알려달라"고 질문하고 진행을 중단한다.

2. **cwd 검증**: 현재 작업 디렉토리(cwd)가 대상 앱 repo의 루트인지 확인한다. 판정 기준은 `.git/`이 cwd 바로 아래에 있는지다. 아니면 중단하고 `autoqa 스킬은 대상 앱 repo 루트에서 실행해야 합니다 — cwd: <현재 경로>`라고 안내한다.

3. **엔진 실행**: `<엔진 폴더>/autoqa.py --repo <cwd>`를 다음 형태로 실행한다:

   ```
   uv -q run "<엔진 폴더>/autoqa.py" --repo "$(pwd)"
   ```

4. **출력 요약 보고**: `autoqa.py`(+내부 호출되는 `error-to-autofix.py`)는
   성공 시 stdout에 아무것도 출력하지 않는다 — exit code와 생성물로
   판단해 요약한다:
   - exit 0 → 정상 종료. `issues/` 아래 새로 생긴 `autofix-#.md` 파일이
     있으면 그 파일명을 보고 (없으면 "이번 회차에 새로 만든 항목 없음")
   - exit 1 → preflight 실패. stderr 메시지를 그대로 전달
   - exit 3 → 락 선점(이미 qa 실행 중). stderr 메시지를 그대로 전달

## 금지

이 스킬은 issue 본문을 작성하거나 코드를 직접 고치는 일을 하지 않는다. qa 스트림은 로그를 읽어 `issues/autofix-#.md`를 새로 만들 뿐이며, 구현/수정은 그 결과 파일을 사람이 (또는 `acpd`가) 다루도록 그대로 넘긴다.

## 충돌 방지

이 `/autoqa` 트리거는 smarthome 등 개별 repo에 들어 있는 `autofix.bat`(린트 스크립트)와 무관하다. 그쪽이 LLM 스크립트인지 단순 lint인지와 관계없이 본 스킬은 autoqafix 엔진만 호출한다.