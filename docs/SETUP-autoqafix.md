# SETUP-autoqafix.md

사람이 새 머신 / 새 repo에 autoqafix 스위트를 배치할 때 따라 하는 단일 문서.
각 항목 끝에 있는 `[<autosdlc>]` 같은 경로는 `~/git/autosdlc` (또는 autosdlc
클론 위치)로 해석.

## 1. 사전 준비

- **Python 패키지 매니저**: `uv` 설치
  - Linux/WSL: `curl -LsSf https://astral.sh/uv/install.sh | sh`
  - Windows PowerShell: `irm https://astral.sh/uv/install.ps1 | iex`
- **래퍼 디렉토리**: `<autosdlc>/skills/autoqafix/wrappers/` 의
  `claudecli.sh`, `antigravitycli.sh`, `qwencli.sh`, `minimaxcli.sh` 등
  사용 래퍼가 PATH에 있어야 함. (또는 `<autosdlc>/install.sh` 로 일괄 설치.)
- **git identity**: `git config --global user.name/email` 설정
- **autosdlc 클론 위치**: `~/git/autosdlc` 권장. 다른 위치여도 되고 그때마다
  `<autosdlc>` 표기를 실제 경로로 치환하면 됨.

## 2. 점검 순서

**전제**: 모든 명령은 `cwd`를 **대상 앱 repo 루트**로 두고 실행한다.

```bash
cd <target-repo>   # 항상 여기서 시작

# (1) 환경 + 처리 결과 종합 진단
bash <autosdlc>/autoqafix-doctor.sh

# (2) 사용 중인 LLM ping (크레딧 소모 — 한 사이클 1회)
bash <autosdlc>/skills/autoqafix/wrappers/ping-claudecli.sh
bash <autosdlc>/skills/autoqafix/wrappers/ping-qwencli.sh
# 기타 사용 래퍼도 같은 패턴

# (3) 픽스처 기반 회귀 (대상 repo의 verify-issue-*.sh 전체)
for f in regression-tests/verify-*.sh; do bash "$f" || echo "FAIL $f"; done
```

## 3. Windows production 배치

Windows 머신에서 무인으로 돌릴 때:

- `Win+R` → `shell:startup` 폴더에 지름길(shortcut) 생성
- **대상**: `<autosdlc>\autodev-loop.bat --reboot-on-fix`
  (역할별로 다름 — autofix 스트림은 `<autosdlc>\autofix-loop.bat`,
   QA는 `<autosdlc>\autoqa-loop.bat`)
- **"시작 위치" = 대상 앱 repo 루트** ← 이게 cwd 규약의 전부. 다른 위치면
  의도한 repo가 아니라 다른 repo를 잘못 처리한다. Windows 지름길의
  "Start in" 필드가 바로 이 값.
- **재시동 폭주 가드**: 한 사이클이 끝나면 정상 종료(루프는 일정 간격으로
  깨어나 1회전을 도는 형태). 같은 머신 + 같은 repo에 두 인스턴스를 띄우면
  같은 작업을 두 번 보고·수정함. 항상 한 인스턴스만.

## 4. WSL 수동 사용

대상 앱 repo에서 1회형으로 직접:

```bash
<autosdlc>/autoqa.sh    # QA 1회 — 로그 → autofix 스트림 보고
<autosdlc>/autofix.sh   # autofix 스트림 한 항목 구현
<autosdlc>/autodev.sh   # issue 스트림 한 항목 구현
```

무인 주기 루프는 같은 이름에 `-loop` 접미사 붙은
`<autosdlc>/autodev-loop.sh`, `<autosdlc>/autofix-loop.sh` 등을 사용.

## 5. Claude Code 스킬

대상 앱 repo의 Claude Code 세션에서 (각 스킬은 repo-local
`.claude/skills/<name>/SKILL.md`):

- **`/autoqafix`** — qa + fix + dev 통합 doctor (1회 진단 + 가능하면 즉시 처리)
- **`/autoqa`** — QA 1회
- **`/autofix`** — autofix 1회
- **`/autodev`** — dev 1회
- **`/autotdd`** — `tdd2 + acpd`를 한 이슈에 대해 연속 실행 (구현 + archive + push)
- **`/autotddreview`** — 다중 모델 리뷰 사이클 (구현 → 다중 리뷰 → 종합 → 재구현)

## 6. 운영 규약 요약

- **스트림 2개**: 사람 작성 `issue-N`, agent 보고 `autofix-N`. 번호는 스트림별 독립.
- **상태 태그** (파일명 규약 v2 — 정본: [`docs/spec/spec-issue-filenames.md`](./spec/spec-issue-filenames.md)):
  - 태그 없음 → 기계 대상 (pending)
  - `__STATE-manual` → 사람 직접 처리
  - `__STATE-agent-failed` → 사람이 실패 기록 읽고 보강 후 태그 제거 후 재시도
  - `__STATE-later` → 사람이 미룸 (태그 제거로 다시 대기열로)
- **용어 + 설계 본문**: [`<autosdlc>/CONTEXT.md`](../CONTEXT.md),
  [`<autosdlc>/docs/autoqafix-design.md`](./autoqafix-design.md)

## 7. 알려진 정리 작업

- `smarthome-project/autofix.bat` (그 repo의 lint 스크립트)는 본 스위트의
  `autofix.sh` 와 이름이 충돌한다. 해당 repo에서 사람이 `lint.bat` 등으로
  개명할 것 (본 repo 작업 아님).
