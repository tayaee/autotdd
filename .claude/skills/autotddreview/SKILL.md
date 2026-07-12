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
2. `issues/issue-<N>.md` exists for every requested issue number

If any check fails, abort with a clear message. Same pattern as `/autodev`.

## Per-issue flow

For each issue `N`, in order. Each step's "done check" is file-based — skip the step if the file already exists with non-empty content.

### Step 1 — Coder MVP (skip if done)

**Done check**: `regression-tests/verify-issue-N.sh` exists AND `issues/issue-N.md` has the `## 구현 결과` placeholder replaced with real content (the `(미정)` marker absent).

If not done:
The execution session runs `/autotdd <N>` inline (or `/autotdd <N> worktree` if the `worktree` keyword was provided). Wait for it to complete.

### Step 2 — Reviewers (parallel, skip done ones)

**Done check** (per reviewer `X`): `issues/issue-N-code-review-by-<X>.md` exists and is non-empty (where `<X>` is the base model name, or `self` for self-review).

For each undone reviewer, launch:
- **External Reviewers**: For each reviewer `<X>`, launch in parallel:
  ```bash
  /home/user1/git/harness-project/.local/bin/<X>-cli.sh -p "issue-<N>의 구현에 대해 코드 품질 감사를 수행하여 issues/issue-<N>-code-review-by-<X>.md 파일을 작성해. 본문 첫 줄에 자기 모델명(버전 포함)을 기입해야 함."
  ```
- **Self-Review**: If no reviewers were specified, launch a subagent in a new context (do not review inline in the same conversation) to write:
  `issues/issue-N-code-review-by-self.md`. The prompt must instruct the subagent to perform a code quality audit of issue N's implementation, and write the report to `issues/issue-N-code-review-by-self.md`, including its model name (with version) in the first line of the file.

Failure of one reviewer does NOT stop the others (continue-with-partial). When all parallel launches return, verify each output file exists and is non-empty. Note any failures for step 3.

### Step 3 — Planner (skip if done)

**Done check**: `issues/issue-N-feedback-review.md` exists and is non-empty.

If not done:
The execution session synthesizes the review files inline:
Read all available review files matching `issues/issue-N-code-review-by-*.md`. Categorize findings into `must-fix`, `good-to-fix`, and `reject`. Then, use the `to-tickets` skill to write the fix plan to `issues/issue-N-feedback-review.md`.

If any reviewer files are missing (from failed reviewers in Step 2), prepend a note in the planning context: "Note: The reviewer file for <failed-reviewer> was unavailable. Synthesize from the surviving files."

### Step 4 — Coder re-fix (skip if done)

**Done check**: every `issues/issue-N-code-review-by-*.md` and `issues/issue-N-feedback-review.md` file has been moved to `issues/archive/<YYYY>/<MM>/<DD>/`.

If not done:
The execution session runs:
- Process all must-fix and good-to-fix tickets created from `issues/issue-N-feedback-review.md` by calling `/autotdd` (passing `worktree` if the original run specified `worktree`).
- After completing all tickets, archive the review files `issues/issue-N-code-review-by-*.md` and `issues/issue-N-feedback-review.md` to `issues/archive/YYYY/MM/DD/` using `aacp`.

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
