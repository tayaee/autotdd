---
name: autotddreview
description: Multi-model implementation → review → synthesis → re-fix loop, fully unattended per issue. Use when the user says "/autotddreview", "autotddreview #", or gives issue numbers (e.g., `autotddreview 21 22 23 minimax sonnet`). One issue fully finished before the next starts; reviewers within an issue run in parallel. Coupled to harness-project wrappers at /home/user1/git/harness-project/.local/bin/.
---

# autotddreview — multi-model review loop, unattended

Implements a 4-step cycle for each issue number, fully unattended:

1. **Coder MVP** — execution session runs `/autotdd <N>` inline
2. **Reviewers N** — N models (parallel) each write a code review file. If no reviewers are specified, it defaults to a self-review (using a subagent in a new context).
3. **Planner** — execution session synthesizes reviews into a fix plan inline, using the `to-tickets` skill
4. **Coder re-fix** — execution session runs the plan inline using `/autotdd`, and archives review files

Issues run **sequentially**. Reviewers within an issue run **in parallel**.
The coder steps (Step 1 and Step 4), the planner step (Step 3), and re-fix are all handled inline by the executing session.
Pure orchestration — no secrets are held by this skill (see "Coupling to harness-project" below).

## Coupling to harness-project

This skill calls model wrappers that live in `/home/user1/git/harness-project/.local/bin/`.
The wrapper binaries are named `<name>-cli.sh` (where `<name>` is the base model name like `sonnet`, `minimax`, `qwen`, `gemini`, `fable`, `deepseek`, `haiku`, `opus`).

Before starting the run, all specified reviewers must be validated: check if `/home/user1/git/harness-project/.local/bin/<name>-cli.sh` exists and is executable. If any of them are missing or not executable, abort the entire run immediately.

## Argument parsing

Arguments are parsed by positional tokens, categorised by shape (order does not matter):

- **Integer tokens**: Issue numbers (at least one is required, otherwise abort).
- **`worktree`**: Isolation keyword.
- **Other tokens**: Reviewer model names (base names, e.g., `minimax`, `sonnet`).

If no reviewer names are specified, the run defaults to a **self-review**.
Note: The old options (model, coder, reviewers, and planner with double dashes) are completely removed. There is no backward compatibility.

Examples:

- `autotddreview 21` — Runs issue 21 with self-review.
- `autotddreview 21 22 23 minimax sonnet` — Runs issues 21, 22, and 23 sequentially. Reviewers are minimax and sonnet (running in parallel).
- `autotddreview 21 22 23 worktree minimax` — Runs issues 21, 22, and 23 in worktree isolation mode, with minimax as the reviewer.

## cwd validation

Run from inside the target repo (any subdirectory). Verify:

1. `cwd` contains `.git/`
2. `issues/issue-<N>.md` (or the unique tag-less `issues/issue-<N>-<slug>.md` — see `docs/spec/spec-issue-filenames.md`) exists for every requested issue number

If any check fails, abort with a clear message. Same pattern as `/autodev`.

## Per-issue flow

For each issue `N`, in order. Each step's "done check" is file-based — skip the step if the file already exists with non-empty content.

### Step 1 — Coder MVP (skip if done)

**Done check**: `regression-tests/verify-issue-N.sh` exists AND `issues/issue-N.md` has the `## 구현 결과` placeholder replaced with real content (the `(미정)` marker absent).

If not done:
The execution session runs `/autotdd <N>` inline (or `/autotdd <N> worktree` if the `worktree` keyword was provided). Wait for it to complete.

### Step 2 — Reviewers (parallel, skip done ones)

파일명 규약의 단일 정본은 `docs/spec/spec-issue-filenames.md`다.

**Done check** (per reviewer `X`): `issues/issue-N__TYPE-code-review__BY-<X>.md` exists and is non-empty (where `<X>` is the base model name, or `self` for self-review — `__BY-` 값은 항상 래퍼 base명이며 버전명은 쓰지 않는다).

#### 리뷰어 프롬프트 — 4부 구조 (외부 래퍼·셀프 리뷰 공통)

실행 세션이 아래 4부를 조립해 하나의 프롬프트로 전달한다. 목적은 추측
리뷰의 구조적 차단 — 리뷰 사이클은 티켓 수백 개에 걸쳐 반복되므로 한
번에 다 찾을 필요가 없고, 확실한 것만 잡는 게 중요하다.

**① 환경 사실**:
- 대상 리포의 Python 버전을 `.python-version`에서, 없으면
  `pyproject.toml`의 `requires-python`에서 읽어 프롬프트에 명시한다.
  준수 수준 판정: 버전이 3.12 미만이면 그 버전 준수를 요구하고, 3.12
  초과면 언어 준수 수준을 3.12로 캡한다. (둘 다 없으면 "버전 정보 없음
  — 문법 세대 지적 금지"라고 명시.)
- "이 코드는 이미 ruff+pyright+pytest+회귀 스크립트를 통과한 상태"임을
  알린다.

**② 리뷰 범위**: 기계가 못 잡는 것만 — 로직 오류, 스펙(이슈 요구사항)
불일치, 보안(OWASP Top 10 렌즈), 동시성·경계조건. **ruff/pyright가 잡는
스타일·타입 지적은 보고 금지** (파이프라인의 다른 단계 몫).

**③ 증거 계약**: finding마다 필수 3요소 —
- `파일:라인` + 실제 **코드 인용**
- 문제가 재현되는 구체 **실패 시나리오** (입력/상태 → 잘못된 결과)
- **확인 방법** (실행·재현 절차)

그리고 명시: "확인하지 못한 것은 쓰지 마라. 리뷰 사이클은 반복되므로
이번에 다 찾을 필요 없다 — **누락보다 오판이 비싸다**."

**④ 구조화 finding 포맷**: **자유 산문 금지** — finding당 고정 필드
(파일:라인 / 코드 인용 / 실패 시나리오 / 확인 방법 / 심각도 제안
`must-fix`|`good-to-fix`)를 표 또는 고정 섹션으로 강제. Step 3 플래너가
기계적으로 판정할 수 있는 형태여야 한다.

공통 유지 지시: 본문 첫 줄에 자기 모델명(버전 포함)을 기입.

#### 실행

For each undone reviewer, launch:
- **External Reviewers**: For each reviewer `<X>`, launch in parallel:
  ```bash
  /home/user1/git/harness-project/.local/bin/<X>-cli.sh -p "<위 4부 구조로 조립한 프롬프트 — 산출 파일: issues/issue-<N>__TYPE-code-review__BY-<X>.md>"
  ```
- **Self-Review**: If no reviewers were specified, launch a subagent in a new context (do not review inline in the same conversation) to write:
  `issues/issue-N__TYPE-code-review__BY-self.md`. 셀프 리뷰 서브에이전트의 프롬프트에도 위 4부 구조를 동일하게 적용한다 (모델명 첫 줄 기입 포함).

Failure of one reviewer does NOT stop the others (continue-with-partial). When all parallel launches return, verify each output file exists and is non-empty. Note any failures for step 3.

### Step 3 — Planner (skip if done)

**Done check**: `issues/issue-N__TYPE-refix-plan.md` exists and is non-empty.

If not done:
The execution session synthesizes the review files inline:
Read all available review files matching `issues/issue-N__TYPE-code-review__BY-*.md`. Categorize findings into `must-fix`, `good-to-fix`, and `reject`. Then, use the `to-tickets` skill to write the fix plan to `issues/issue-N__TYPE-refix-plan.md`.

If any reviewer files are missing (from failed reviewers in Step 2), prepend a note in the planning context: "Note: The reviewer file for <failed-reviewer> was unavailable. Synthesize from the surviving files."

### Step 4 — Coder re-fix (skip if done)

**Done check**: every `issues/issue-N__TYPE-*.md` file (code-review들과 refix-plan) has been moved to `issues/archive/<YYYY>/<MM>/<DD>/` — 파일명 그대로, `git mv`로.

If not done:
The execution session runs:
- Process all must-fix and good-to-fix tickets created from `issues/issue-N__TYPE-refix-plan.md` by calling `/autotdd` (passing `worktree` if the original run specified `worktree`).
- After completing all tickets, archive the review files `issues/issue-N__TYPE-code-review__BY-*.md` and `issues/issue-N__TYPE-refix-plan.md` to `issues/archive/YYYY/MM/DD/` using `aacp`.

## Failure policy

- **Issue-level fail-fast**: if step 1 (MVP) fails, skip all remaining steps for that issue and move to next. If step 3 (planner) or step 4 (re-fix) fails, skip remaining and move to next.
- **Step-level continue-with-partial**: in step 2, if some reviewers fail, continue with the survivors and pass that info to the planner so it can account for missing inputs.

When continuing past failures, log the failure clearly in the final summary, but don't abort the overall run unless the failure is structural (e.g., wrapper not found, cwd invalid).

## Idempotency

Every step's "done check" is file-based. Re-running `autotddreview N` after a partial run will skip already-finished steps and resume from where it left off. To force re-do, `rm` the relevant output file(s) first.

## Multi-issue behavior

Issues are processed strictly sequentially: `autotddreview 21 22 23` finishes 21 fully (all 4 steps), then 22, then 23. Within each issue, reviewers run in parallel.

## Output / report

After all issues complete (or fail), emit a summary table:

| Issue | MVP | Reviews | Plan | Re-fix | Status |
|---|---|---|---|---|---|
| 21 | ✓ | 3/3 | ✓ | ✓ | DONE |
| 22 | ✓ | 2/3 (gemini failed) | ✓ (partial input) | ✓ | DONE |
| 23 | ✗ (coder timeout) | — | — | — | FAILED |

## Forbidden

- Do NOT make this SKILL.md hold secrets. All API keys live in the wrappers.
- Do NOT skip the done-check — re-running is the whole point of unattended.
- Do NOT run reviewers serially when they could be parallel (wall time matters).
- Do NOT commit/push/merge to autotdd or harness-project as part of this skill's flow. The coder's own `/autotdd` calls handle that for the issue repo. This skill only manipulates `issues/issue-*.md` files in cwd.
