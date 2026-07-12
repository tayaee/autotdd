---
name: autorevfix
description: Multi-model implementation → review → synthesis → re-fix loop, fully unattended per issue. Use when the user says "/autorevfix", "autorevfix #", or gives issue numbers (e.g., `autorevfix 21 22 23 --model sonnet --reviewers sonnet,gemini,minimax`). One issue fully finished before the next starts; reviewers within an issue run in parallel. Coupled to harness-project wrappers at /home/user1/git/harness-project/.local/bin/.
---

# autorevfix — multi-model review loop, unattended

Implements a 4-step cycle for each issue number, fully unattended:

1. **Coder MVP** — one model writes the implementation
2. **Reviewers N** — N models (parallel) each write a code review file
3. **Planner** — one model synthesizes reviews into a fix plan
4. **Coder re-fix** — same coder runs the plan, archives review files

Issues run **sequentially**. Reviewers within an issue run **in parallel**.
The coder does both step 1 and step 4. Pure orchestration — no secrets are
held by this skill (see "Coupling to harness-project" below).

## Coupling to harness-project

This skill calls 5 model wrappers that live in
`/home/user1/git/harness-project/.local/bin/`:

- **Outer (base name, secrets-free)**: `sonnet-cli.sh`, `minimax-cli.sh`,
  `qwen-cli.sh`, `gemini-cli.sh`, `fable-cli.sh`
- **Inner (version-fixed, secrets held by the wrappers, not this skill)**:
  `sonnet5-cli.sh`, `minimax3-cli.sh`, `qwen36-cli.sh`, `gemini35-cli.sh`,
  `fable5-cli.sh`

`bash regression-tests/verify-issue-35.sh` confirms the wrappers are still
in place. If they're missing or not executable, abort and tell the user.
This coupling is intentional and machine-specific — generalizing is a
future refactor (memory `secrets-segregation-autotdd-harness-project`).

## Argument parsing

| Form | Meaning |
|---|---|
| `autorevfix <issue#> [<issue#> ...]` | Run full cycle on each issue, in order |
| `--model NAME` | Top-level default for the three option flags. Default: `minimax` (= `minimax3`). |
| `--coder NAME` | MVP implementer AND re-fixer (same model does both). Default: `--model`. |
| `--reviewers a,b,c` | Reviewer list, comma-separated. Default: `--model` (single-model self-review, allowed). |
| `--planner NAME` | Synthesizer of reviews into a fix plan. Default: `--model`. |

`NAME` is the base model name (`sonnet`, `minimax`, `gemini`, `qwen`, `fable`).
The version is resolved by the wrapper indirection (`sonnet` → `sonnet5` etc.).

Examples:

- `autorevfix 21` — coder=minimax3, reviewers=[minimax3], planner=minimax3
  (self-review, allowed)
- `autorevfix 21 22 23 --model sonnet --planner fable` —
  coder/reviewers=sonnet5, planner=fable5 (use fable only when credits allow)
- `autorevfix 21 --reviewers sonnet,gemini,minimax` —
  coder/planner=minimax3, three reviewers

## cwd validation

Run from inside the target repo (any subdirectory). Verify:

1. `cwd` contains `.git/`
2. `issues/issue-<N>.md` exists for every requested issue number

If any check fails, abort with a clear message. Same pattern as `/autodev`.

## Per-issue flow

For each issue `N`, in order. Each step's "done check" is file-based — skip
the step if the file already exists with non-empty content.

### Step 1 — Coder MVP (skip if done)

**Done check**: `regression-tests/verify-issue-N.sh` exists AND
`issues/issue-N.md` has the `## 구현 결과` placeholder replaced with real
content (the `(미정)` marker absent).

If not done, run:

```bash
<coder>-cli.sh -p "/autotdd <N>"
```

The coder (in its own Claude session) runs `/autotdd`, which is
implement+verify+archive+commit+push+deploy for that single issue. Wait
for it to complete (typically 5–30 minutes — this is the longest step).

### Step 2 — Reviewers (parallel, skip done ones)

**Done check** (per reviewer `X`): `issues/issue-N-code-review-by-<X-version>.md`
exists and is non-empty. The `<X-version>` is the inner-wrapper version
(`sonnet5`, `gemini35`, etc.), not the base name.

For each undone reviewer, launch **in parallel** by issuing all the Bash
calls in one message. Each reviewer runs:

```bash
<X>-cli.sh -p "issue-<N>의 구현에 대해 코드 품질 감사를 수행하여 issues/issue-<N>-code-review-by-<X-version>.md 파일을 작성해."
```

Failure of one reviewer does NOT stop the others (continue-with-partial).
When all parallel launches return, verify each output file exists and is
non-empty. Note any failures for step 3.

### Step 3 — Planner (skip if done)

**Done check**: `issues/issue-N-feedback-review-by-<P-version>.md` exists
and is non-empty.

If not done:

```bash
<P>-cli.sh -p "issues/issue-<N>-code-review*.md 파일을 평가하여 must-fix, good-to-fix, reject으로 분류하고, must-fix, good-to-fix에 대해 to-tickets 스킬로 수정 계획 issues/issue-<N>-feedback-review-by-<P-version>.md 파일을 작성해"
```

If 1+ reviewer files are missing (reviewer failed in step 2), prepend a
note in the planner's prompt: "Note: N reviewer files were unavailable
(see failures: <list>). Synthesize from the M files that exist."

### Step 4 — Coder re-fix (skip if done)

**Done check**: every `issues/issue-N-code-review-by-*.md` and
`issues/issue-N-feedback-review-by-*.md` file has been moved to
`issues/archive/<YYYY>/<MM>/<DD>/`.

If not done:

```bash
<coder>-cli.sh -p "/autotdd issue-<N> 지적사항 수정용 티켓들 모두 골라서 완료하고, issues/issue-<N>-{code-review,feedback-review}*.md 파일에 대해 aacp 수행해 (archive, add, commit, push)"
```

The coder reads the planner output, picks must/good-to-fix ticket numbers,
runs `/autotdd` on each, then `aacp` archives the review/feedback md files
into `issues/archive/YYYY/MM/DD/`.

## Failure policy

- **Issue-level fail-fast**: if step 1 (MVP) fails, skip all remaining
  steps for that issue and move to next. If step 3 (planner) or step 4
  (re-fix) fails, skip remaining and move to next.
- **Step-level continue-with-partial**: in step 2, if some reviewers fail,
  continue with the survivors and pass that info to the planner so it can
  account for missing inputs.

When continuing past failures, log the failure clearly in the final
summary, but don't abort the overall run unless the failure is structural
(e.g., wrapper not found, cwd invalid).

## Idempotency

Every step's "done check" is file-based. Re-running `autorevfix N` after
a partial run will skip already-finished steps and resume from where it
left off. To force re-do, `rm` the relevant output file(s) first.

## Multi-issue behavior

Issues are processed strictly sequentially: `autorevfix 21 22 23` finishes
21 fully (all 4 steps), then 22, then 23. Within each issue, reviewers
run in parallel.

## Output / report

After all issues complete (or fail), emit a summary table:

| Issue | MVP | Reviews | Plan | Re-fix | Status |
|---|---|---|---|---|---|
| 21 | ✓ | 3/3 | ✓ | ✓ | DONE |
| 22 | ✓ | 2/3 (gemini35 failed) | ✓ (partial input) | ✓ | DONE |
| 23 | ✗ (coder timeout) | — | — | — | FAILED |

## Forbidden

- Do NOT make this SKILL.md hold secrets. All API keys live in the wrappers.
- Do NOT skip the done-check — re-running is the whole point of unattended.
- Do NOT run reviewers serially when they could be parallel (wall time matters).
- Do NOT commit/push/merge to autotdd or harness-project as part of this
  skill's flow. The coder's own `/autotdd` calls handle that for the issue
  repo. This skill only manipulates `issues/issue-*.md` files in cwd.