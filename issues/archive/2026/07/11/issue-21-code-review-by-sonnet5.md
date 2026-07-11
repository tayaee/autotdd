# PR Code Review: Issue-21 Claude Code 트리거 스킬 4종 및 install.sh (Sonnet 5 감사)

본 문서는 [issue-21.md](file:///home/user1/git/autotdd/issues/archive/2026/07/11/issue-21.md)의 구현(커밋 `0cf8961`)에 대한 독립적인 코드 품질 감사 결과다. 스킬 문서(SKILL.md)가 실제로 호출한다고 주장하는 엔진 코드(`.claude/skills/autoqafix/*.py`)까지 직접 대조·재현 실행하여 검증했다.

## 1. 개요

- **대상 커밋**: `0cf8961` (issue-21: Claude Code 트리거 스킬 4종 + install.sh)
- **검토 대상**:
  - [.claude/skills/autoqa/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqa/SKILL.md)
  - [.claude/skills/autofix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autofix/SKILL.md)
  - [.claude/skills/autodev/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autodev/SKILL.md)
  - [.claude/skills/autoqafix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqafix/SKILL.md)
  - [install.sh](file:///home/user1/git/autotdd/install.sh)
  - [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)
  - 대조군: 실제 엔진 코드 `.claude/skills/autoqafix/{autoqa,autofix,autoqafix-doctor}.py`, `autodev.sh`(repo 루트)

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
$ ls .claude/skills/autoqafix/autodev.py
ls: cannot access 'autodev.py': No such file or directory
```

repo 루트에 이미 있는 `autodev.sh`(레거시 런처)를 보면 실제 dev 스트림의 진입점을 알 수 있다:

```bash
# autodev.sh — autofix.py STREAMS / stream_to_role: `issue` → role `dev`
uv -q run ".../autofix.py" --repo "$(pwd)" --stream issue
```

`autofix.py`의 docstring([autofix.py:12-13](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py#L12-L13))도 명시한다: *"Stream is selected by --stream (default autofix; pass `issue` for autodev)."* 즉 dev 스트림은 별도 스크립트가 아니라 `autofix.py --stream issue` 호출이다.

`autodev.py`라는 파일명은 리포 전체에서 이 SKILL.md 두 줄에만 등장하며(`grep -rn "autodev\.py"` 결과 동일), 다른 어디에도 정의되어 있지 않다. **`/autodev`를 트리거하면 3단계(엔진 실행)에서 `uv run`이 파일 없음으로 항상 실패한다** — 이 스킬은 현재 상태로 전혀 동작하지 않는다.

- **권장 조치**: `.claude/skills/autodev/SKILL.md`의 "엔진 실행" 절을 `<엔진 폴더>/autofix.py --repo <cwd> --stream issue`로 수정한다. `autofix`/`autodev` SKILL.md가 동일한 파일(`autofix.py`)을 스트림만 다르게 호출한다는 점을 명확히 문서화해야 한다.

### 2.2. 회귀 테스트가 이 결함을 잡아내지 못하는 구조적 이유

[regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)는 frontmatter 형식, 트리거 문구(`/autodev`), `smarthome` 문구, 금지 문구의 **존재 여부만 정규식으로 검사**할 뿐, SKILL.md 본문이 지시하는 "엔진 실행" 커맨드가 실제로 유효한 파일을 가리키는지는 전혀 검증하지 않는다(`grep -n "엔진 실행\|uv -q run" verify-issue-21.sh` → 결과 없음). 13 PASS / 0 FAIL로 통과했지만, 이는 스킬이 "형식을 갖췄다"는 것만 보증하며 "동작한다"는 것은 보증하지 못한다.

- **권장 조치**: 각 SKILL.md 본문에서 실제로 언급하는 엔진 스크립트 경로(정규식으로 `` `[\w./]+\.py` `` 등을 추출하거나, 최소한 `autofix.py`/`autoqa.py`/`autoqafix-doctor.py` 3개 파일명이 4개 스킬 문서에 정확히 매핑되는지)를 리포지토리에 실제 파일이 존재하는지와 대조하는 assertion을 추가할 것.

---

## 3. P1 — 확인된 문서-구현 불일치

### 3.1. "출력 요약 보고" 토큰 계약이 3개 스킬에서 실제 엔진 출력과 다르다

`autoqa`/`autofix`/`autodev` 세 SKILL.md는 4단계에 동일한 문구를 복붙했다:

```
- `[원인] ...` — 결함 원인
- `[조치] ...` — 권장 조치
- `FIXED=<n>` 또는 `FIXED=` (없음)
- `FAIL <항목>` 줄이 있으면 그 항목을 모두 나열
- `OK <항목>` 요약
```

그러나 실제 stdout을 대조하면:

| 스킬 | 실제 호출 스크립트 | 실제로 찍는 토큰 |
|---|---|---|
| `autoqa` | `autoqa.py` → `error-to-autofix.py` | 없음 (`grep -n 'FIXED=\|\[원인\]\|\[조치\]\|OK \|FAIL '` 두 파일 모두 매치 0건) |
| `autofix`/`autodev` | `autofix.py` | `처리: N건, ...` 요약 줄 + `FIXED=<n>` 뿐. `[원인]`/`[조치]`/`FAIL <항목>`/`OK <항목>`은 [autofix.py:270-278](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autofix.py#L270-L278)에서 wrapper subprocess의 stdout을 캡처해 버릴 뿐 출력하지 않는다 |
| `autoqafix`(doctor) | `autoqafix-doctor.py` | `OK <항목>` / `FAIL <항목>` + `[원인]`/`[조치]` / `WARN` — 이 스킬만 실제로 문서와 일치 |

즉 `[원인]`/`[조치]`/`FAIL`/`OK` 토큰은 `autoqafix-doctor.py` 고유의 출력 계약인데, 복붙 과정에서 `autoqa`/`autofix`/`autodev` SKILL.md에도 그대로 옮겨졌다. 이 세 스킬을 실행하는 LLM은 지시받은 토큰을 찾지 못해 헛되이 파싱을 시도하거나, 존재하지 않는 내용을 있는 것처럼 요약 보고할 위험이 있다.

- **권장 조치**: `autoqa`/`autofix`/`autodev`의 4단계 문구를 각 스크립트의 실제 출력(`처리: N건, ...` 요약 줄과 `FIXED=<n>`, 그리고 qa 스트림은 사실상 무출력이므로 exit code/로그 파일 기준 안내)에 맞게 다시 쓸 것.

### 3.2. install.sh는 깨진(dangling) symlink도 "이미 설치됨"으로 오판한다

[install.sh:37-43](file:///home/user1/git/autotdd/install.sh#L37-L43)은 `[ -L "$dst" ]`(symlink 존재)만 확인하고 그 대상이 실제로 존재하는지, 올바른 repo를 가리키는지는 검사하지 않는다. 직접 재현:

```
$ ln -s "/nonexistent/path/autoqa" "$HOME/.claude/skills/autoqa"
$ bash install.sh
이미 설치됨 (symlink): .../autoqa → /nonexistent/path/autoqa
...
exit=0
```

repo가 이동/재클론되어 옛 경로를 가리키는 symlink가 남아 있어도 `install.sh`는 항상 "이미 설치됨"으로 성공 처리하고 고쳐주지 않는다. "idempotent"(반복 실행해도 동일 상태)는 지켜지지만, 실사용 시나리오(repo 경로 변경, 브랜치 재클론 등)에서 "self-healing"이 되지 않아 사용자는 `/autoqa` 등이 이유 없이 안 열린다는 상황에 빠질 수 있다. install.sh 자체는 종료 코드 0으로 아무 경고도 주지 않는다.

- **권장 조치**: `[ -L "$dst" ]`인 경우에도 `readlink -f "$dst"`가 `$src`(또는 최소한 존재하는 경로)로 resolve되는지 확인하고, 불일치 시 `missing`(경고) 카운트에 포함하거나 자동으로 재연결하도록 개선. gemini35 리뷰가 지적한 절대경로 symlink 문제(3.1.2)와 근본 원인이 겹친다 — repo 이동에 취약한 절대경로 symlink + "존재만 확인하고 유효성은 확인 안 함" 로직이 함께 문제를 키운다.

---

## 4. P2 — gemini35 리뷰와 일치하는 부분 (재확인)

이미 [issue-21-pr-review-by-gemini35.md](file:///home/user1/git/autotdd/issue-21-pr-review-by-gemini35.md)에서 지적된 아래 항목들을 코드 레벨에서 재확인했고, 타당하다고 판단한다:

- [verify-issue-21.sh:144-151](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh#L144-L151): "실 HOME 오염 검증" 루프가 `:` (no-op)만 실행 — 실질적으로 아무것도 검증하지 않는 빈 껍데기.
- [verify-issue-21.sh:112-113](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh#L112-L113): 92번/106번 줄에서 이미 install.sh를 두 번 실행해놓고, exit code만 얻으려고 3번째/4번째 실행을 또 한다. 92/106번 실행 시점에 `$?`를 바로 캡처하면 제거 가능.
- [install.sh:11](file:///home/user1/git/autotdd/install.sh#L11): `set -uo pipefail`만 있고 `set -e`가 없어 `mkdir -p`/`ln -s` 실패 시에도 스크립트가 계속 진행해 잘못된 요약을 낼 수 있다. 3.2에서 확인한 dangling symlink 오판 문제와 함께 보면, install.sh가 "실패를 감지 못 하고 성공으로 보고"하는 패턴이 한 군데가 아니라는 점이 우려된다.

---

## 5. 강점

- 4개 SKILL.md의 구조(frontmatter, 절차 4단계, 금지, 충돌 방지)가 issue-21 요구사항의 4개 항목과 1:1로 대응하며 매우 일관적이다.
- `install.sh`의 symlink-vs-충돌 3분기 처리(symlink 존재/파일·디렉토리 충돌/신규 설치)는 명확하고 읽기 쉽다.
- `verify-issue-21.sh`가 `mktemp -d` + `HOME` 오버라이드로 실제 개발자 홈을 건드리지 않고 `install.sh`를 두 번 실행해 idempotency를 검증하는 격리 전략 자체는 견고하다(단, 3.1의 구조적 한계는 별개).

---

## 6. 종합 결론

이슈에 명시된 승인 기준(frontmatter 유효성, install.sh idempotent, symlink 생성)은 **테스트가 검사하는 범위 안에서는** 모두 충족되어 13 PASS를 받았다. 그러나 그 테스트 범위 자체가 "문서 형식"에 그쳐 있어, **`/autodev` 트리거는 실제로 실행하면 곧바로 실패하는 상태로 병합되었다** (2.1). 이는 마이너 개선이 아니라 issue-21이 신설하겠다고 선언한 4개 트리거 중 1개가 기능하지 않는다는 뜻이다. 추가로 `autoqa`/`autofix`/`autodev`의 출력 요약 계약이 실제 엔진 출력과 어긋나 있어(3.1) 나머지 두 스킬도 "형식은 맞지만 지시대로 동작하면 부정확한 보고를 낳는" 상태다.

**권장**: `autodev/SKILL.md`의 엔진 실행 절을 `autofix.py --stream issue`로 즉시 수정하고, 세 스킬의 출력 토큰 계약을 실제 stdout에 맞게 재작성한 뒤, `verify-issue-21.sh`에 "SKILL.md가 참조하는 스크립트 파일이 실존하는지" 검사를 추가하는 후속 수정을 우선순위로 처리할 것을 권한다.
