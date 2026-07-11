# PR Code Review: Issue-21 Claude Code 트리거 스킬 4종 및 install.sh (Qwen Code 감사)

본 문서는 [issue-21.md](file:///home/user1/git/autotdd/issues/archive/2026/07/11/issue-21.md)의 구현(커밋 `0cf8961`)에 대한 독립적인 코드 품질 감사 결과다. 엔진 코드(`.claude/skills/autoqafix/*.py`)를 직접 대조·재현 실행하여 검증했다.

## 1. 개요

- **대상 커밋**: `0cf8961` (issue-21: Claude Code 트리거 스킬 4종 + install.sh)
- **검토 대상**:
  - [.claude/skills/autoqa/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqa/SKILL.md)
  - [.claude/skills/autofix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autofix/SKILL.md)
  - [.claude/skills/autodev/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autodev/SKILL.md)
  - [.claude/skills/autoqafix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqafix/SKILL.md)
  - [install.sh](file:///home/user1/git/autotdd/install.sh)
  - [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)
  - 대조군: 실제 엔진 코드 `.claude/skills/autoqafix/{autoqa,autofix,autoqafix-doctor}.py`

---

## 2. P0 — 확인된 심각한 결함

### 2.1. `/autodev` 트리거가 존재하지 않는 파일을 실행하려 한다 (즉시 실패)

[.claude/skills/autodev/SKILL.md:19-22](file:///home/user1/git/autotdd/.claude/skills/autodev/SKILL.md#L19-L22):

```
3. **엔진 실행**: `<엔진 폴더>/autodev.py --repo <cwd>`를 다음 형태로 실행한다:
   uv -q run "<엔진 폴더>/autodev.py" --repo "$(pwd)"
```

`.claude/skills/autoqafix/` 엔진 폴더 안에 `autodev.py`는 **존재하지 않는다**:

```
$ ls .claude/skills/autoqafix/*.py
autofix.py  autoqa.py  autoqafix-doctor.py  autoqafix_core.py  error-to-autofix.py  log-scan.py  role-loop.py  select-llm.py  usage-claudecli.py  usage-minimaxcli.py  usage-qwencli.py
```

`autodev.py`라는 파일명은 리포 전체에서 이 SKILL.md 두 줄에만 등장하며, 다른 어디에도 정의되어 있지 않다.

repo 루트에 이미 있는 `autodev.sh`(레거시 런처)가 실제 동작 방식을 명시한다([autodev.sh:20-21](file:///home/user1/git/autotdd/autodev.sh#L20-L21)):

```bash
uv -q run "$PY_SCRIPT" --repo "$(pwd)" --stream issue
```

여기서 `PY_SCRIPT`는 `.claude/skills/autoqafix/autofix.py`다. `autofix.py`의 docstring([autofix.py:6-13](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py#L6-L13))도 명시한다: *"Stream is selected by --stream (default autofix; pass `issue` for autodev)."* 즉 dev 스트림은 별도 스크립트가 아니라 `autofix.py --stream issue` 호출이다.

**`/autodev`를 트리거하면 3단계(엔진 실행)에서 `uv run`이 파일 없음으로 항상 실패한다** — 이 스킬은 현재 상태로 전혀 동작하지 않는다.

- **권장 조치**: `.claude/skills/autodev/SKILL.md`의 "엔진 실행" 절을 `<엔진 폴더>/autofix.py --repo <cwd> --stream issue`로 수정한다. `autofix`/`autodev` SKILL.md가 동일한 파일(`autofix.py`)을 스트림만 다르게 호출한다는 점을 명확히 문서화해야 한다.

### 2.2. `autoqa` SKILL.md의 출력 토큰 계약이 실제 엔진 출력과 완전히 불일치

[.claude/skills/autoqa/SKILL.md:28-34](file:///home/user1/git/autotdd/.claude/skills/autoqa/SKILL.md#L28-L34)는 다음 토큰을 요약 보고하라고 지시한다:

```
- `[원인] ...` — 결함 원인
- `[조치] ...` — 권장 조치
- `FIXED=<n>` 또는 `FIXED=` (없음) — 처리된 항목 수
- `FAIL <항목>` 줄이 있으면 그 항목을 모두 나열
- `OK <항목>` 요약
```

그러나 실제 `autoqa.py`([autoqa.py:1-60](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqa.py))는 stdout에 **아무 토큰도 출력하지 않는다**:

1. preflight 실패 → stderr로 메시지 + `sys.exit(1)`
2. 락 획득 실패 → stderr로 메시지 + `sys.exit(3)`
3. 정상 경로 → `error-to-autofix.py` 서브프로세스 실행 후 그 returncode로 `sys.exit()`

`autoqa.py`와 `error-to-autofix.py` 모두 `grep -n 'FIXED=\|\[원인\]\|\[조치\]\|OK \|FAIL '` 결과 **매치 0건**. 즉 LLM이 지시받은 토큰을 찾지 못해 헛되이 파싱을 시도하거나, 존재하지 않는 내용을 있는 것처럼 요약 보고할 위험이 있다.

- **권장 조치**: `autoqa`의 4단계 문구를 실제 출력(없음 — exit code와 stderr만 기준)에 맞게 재작성하거나, `autoqa.py`에 실제 출력 계약을 추가한다.

---

## 3. P1 — 확인된 문서-구현 불일치

### 3.1. `autofix` SKILL.md의 출력 토큰 계약이 실제 엔진 출력과 다름

`autofix` SKILL.md도 `[원인]`/`[조치]`/`FAIL`/`OK` 토큰을 보고하라고 지시하지만, 실제 `autofix.py` stdout 출력은 다음 두 줄뿐이다([autofix.py:400-404](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py#L400-L404)):

```
처리: N건, 수동 분류: M건, 건너뜀: K건, 스탬프 추가: S건, 오류: E건
FIXED=<fixed>
```

`[원인]`/`[조치]`/`FAIL`/`OK` 토큰은 `autoqafix-doctor.py`([autoqafix-doctor.py:47-66](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L47-L66)) 고유의 출력 계약인데, 복붙 과정에서 `autofix` SKILL.md에도 그대로 옮겨졌다. autofix.py wrapper subprocess의 stdout을 캡처해 버리므로 이 토큰들이外层에 도달하지 않는다.

- **권장 조치**: `autofix`의 4단계 문구를 실제 stdout(`처리: N건...` + `FIXED=<n>`)에 맞게 다시 쓴다.

### 3.2. install.sh — `set -e` 부재 + 깨진 symlink 오판

[install.sh:11](file:///home/user1/git/autotdd/install.sh#L11): `set -uo pipefail`만 있고 `set -e`가 없다. `mkdir -p`/`ln -s` 실패 시에도 스크립트가 계속 진행해 잘못된 요약을 낼 수 있다.

[install.sh:37-43](file:///home/user1/git/autotdd/install.sh#L37-L43): `[ -L "$dst" ]`만 확인하고 대상이 실제로 존재하는지 검사하지 않는다.

재현:

```bash
$ ln -s "/nonexistent/path/autoqa" ~/.claude/skills/autoqa
$ bash install.sh
이미 설치됨 (symlink): ~/.claude/skills/autoqa → /nonexistent/path/autoqa
exit=0
```

repo가 이동/재클론되어 옛 경로를 가리키는 symlink가 남아 있어도 `install.sh`는 항상 "이미 설치됨"으로 성공 처리하고 고쳐주지 않는다.

- **권장 조치**: `set -e` 추가 + `[ -L "$dst" ]` 시 `readlink -f "$dst"`가 존재하는 경로로 resolve되는지 확인하고, 불일치 시 재연결하도록 개선.

### 3.3. install.sh — 절대경로 symlink: 프로젝트 이동 시 깨짐

[install.sh:20](file:///home/user1/git/autotdd/install.sh#L20): `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`로 절대경로를 구하고, [install.sh:50](file:///home/user1/git/autotdd/install.sh#L50): `ln -s "$src" "$dst"`로 절대경로 symlink를 생성한다.

프로젝트 디렉토리를 이동하면 기존 `~/.claude/skills/*` 링크가 모두 깨진다.

- **권장 조치**: `ln -s --relative` 또는 상대경로 방식으로 링크를 생성하거나, 최소한 repo 이동 시 재설치 안내 메시지를 제공한다.

---

## 4. P2 — 기존 리뷰(gemini35/sonnet5)와 일치하는 부분 (재확인)

### 4.1. verify-issue-21.sh의 구조적 한계

- **[verify-issue-21.sh:144-151](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh#L144-L151)**: "실 HOME 오염 검증" 루프가 `:` (no-op)만 실행 — 실질적으로 아무것도 검증하지 않는 빈 껍데기.
- **[verify-issue-21.sh:112-113](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh#LL144-L145)**: 이미 92번/106번 줄에서 install.sh를 두 번 실행해놓고, exit code만 얻으려고 3번째/4번째 실행을 또 한다. `$?`를 바로 캡처하면 제거 가능.
- **[verify-issue-21.sh:68](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh#L68)**: `grep -qE '금지|하지 말|쓰지 말|고치지 말|하지마'` — 한국어에만 의존하는 정규식. 향후 영문 번역 시 오작동.

### 4.2. verify-issue-21.sh의 강점 재확인

- `mktemp -d` + `HOME` 오버라이드로 실제 개발자 홈을 건드리지 않는 격리 전략 자체는 견고하다.
- `trap cleanup EXIT`로 임시 디렉토리 안전 제거가 잘 되어 있다.

### 4.3. SKILL.md 구조의 강점 재확인

- 4개 SKILL.md의 구조(frontmatter, 절차 4단계, 금지, 충돌 방지)가 issue-21 요구사항의 4개 항목과 1:1로 대응하며 매우 일관적이다.
- 각 SKILL.md의 줄 수(autoqa/autofix/autodev: 37줄, autoqafix: 36줄)가 적정 범위에 있으며 과다한 복붙 없이 핵심 정보만 담고 있다.

---

## 5. 강점

1. **SKILL.md 설계의 일관성**: 4개 스킬 모두 동일한 4단계 구조(엔진 위치 → cwd 검증 → 엔진 실행 → 출력 요약) + 금지 + 충돌 방지로, LLM이 예측 가능하게 해석할 수 있다.
2. **install.sh의 3분기 처리**: symlink 존재 / 파일·디렉토리 충돌 / 신규 설치 — 세 경우를 명확히 분기하여 읽기 쉽다.
3. **verify-issue-21.sh의 격리 전략**: `mktemp -d` + `HOME` 오버라이드로 실제 홈을 오염시키지 않는 테스트 설계 자체는 견고하다.
4. **smarthome 충돌 방지 명시**: description과 본문 모두에서 "smarthome 등 개별 repo의 autofix.bat와 무관"을 반복 명시하여 이름 충돌 혼동을 막았다.

---

## 6. 종합 결론

이슈에 명시된 승인 기준(frontmatter 유효성, install.sh idempotent, symlink 생성)은 **테스트가 검사하는 범위 안에서는** 모두 충족되어 13 PASS를 받았다. 그러나 세 군데의 P0/P1 결함이 있다:

| 우선순위 | 결함 | 영향 |
|---|---|---|
| **P0** | `/autodev` 엔진 파일(`autodev.py`) 부재 | `/autodev` 트리거 1개가 아예 동작하지 않음 |
| **P0** | `autoqa` 출력 토큰 계약 완전히 허위 | LLM이 존재하지 않는 토큰을 찾아 헤맴 |
| **P1** | `autofix` 출력 토큰 계약 불일치 | LLM이 잘못된 토큰으로 보고 시도 |
| **P1** | install.sh `set -e` 부재 + dangling symlink 오판 | 실패를 감지 못 하고 성공 보고 |
| **P1** | install.sh 절대경로 symlink | repo 이동 시 깨짐 |

**권장**: `autodev/SKILL.md`의 엔진 실행 절을 `autofix.py --stream issue`로 즉시 수정하고, 세 스킬의 출력 토큰 계약을 실제 stdout에 맞게 재작성한 뒤, `verify-issue-21.sh`에 "SKILL.md가 참조하는 스크립트 파일이 실존하는지" 검사를 추가하는 후속 수정을 우선순위로 처리할 것을 권한다.

---

## 7. 검증 방법 및 데이터

본 감사에서 사용된 주요 검증:

```bash
# autodev.py 부재 확인
ls .claude/skills/autoqafix/autodev.py  → No such file
grep -rn 'autodev\.py' --include='*.py' --include='*.sh' → SKILL.md 2줄만

# autoqa.py stdout 토큰 확인
grep -n 'FIXED=\|\[원인\]\|\[조치\]\|OK \|FAIL ' autoqa.py → 매치 0건

# autofix.py 실제 stdout 출력
grep -n 'print.*FIXED\|print.*처리' autofix.py → line 400(FIXED=), line 404(FIXED=)

# autoqafix-doctor.py 토큰 (이 스킬만 실제 일치)
grep -n 'print.*OK\|print.*FAIL\|print.*\[원인\]\|print.*\[조치\]\|print.*WARN' autoqafix-doctor.py → lines 47-66

# install.sh set 옵션
grep -n 'set -' install.sh → line 11: set -uo pipefail (set -e 없음)
```
