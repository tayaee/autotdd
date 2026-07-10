---
name: acpd
description: Archive an implemented issue, stage remaining tracked changes, commit code+archive together, push, and deploy to dev. Use when the user says "/acpd", "acpd #", or asks to archive+commit+push+deploy an issue (typically right after /tdd2 leaves changes staged).
---

# acpd — archive, add -u, commit, push, deploy

Merges a `/tdd2`-staged issue into `main` and deploys it to dev, in one
commit. Companion skill: `/tdd2` (implements, stops at `git add`).
Combined skill that chains both, per issue, fully automatically:
`/autotdd`.

**Precondition**: code changes for the issue are already staged
(`git add`, not yet committed) — that's where `/tdd2` stops. This
skill does the rest.

## A naming note before anything else

`acpd` is a sequence of **five** steps: **A**rchive the issue file,
git **A**dd -u, **C**ommit, **P**ush, **D**eploy. This skill's own
script only implements the first four — it's called `aacp.sh`
(`.ps1`/`.bat` too), named after exactly what it does. The fifth step,
Deploy, is **not** this skill's logic: it's each target repo's own
responsibility to provide a deploy entry point. `aacp.sh`'s last step
just looks for one and calls it — it never generates or scaffolds one.
They live in different places:

| | Path | What it is |
|---|---|---|
| This skill's script | `.claude/skills/acpd/aacp.{sh,ps1,bat}` | What you invoke to run the whole archive→add→commit→push→deploy pipeline |
| Target repo's script (project-provided) | `<target-repo>/deploy.{sh,ps1,bat}` or `<target-repo>/deploy-to-env.{sh,ps1,bat}` | The project's own `--env <env>` deploy hook, called by the skill's script at the very end, if it exists |

Everywhere below, "this script" / "the acpd script" means the former.

## Run it

### Explicit issue number — no prompts

```bash
bash .claude/skills/acpd/aacp.sh <issue-number> <commit-summary...>
```

```bash
bash .claude/skills/acpd/aacp.sh 42 "KP115 전력 캐시 만료 버그 수정"
```

On a Windows host without bash/WSL, use `aacp.ps1` (native
PowerShell port) or `aacp.bat` (thin dispatcher to `aacp.ps1`) —
same arguments, same behavior. `aacp.sh` is the canonical,
most-exercised implementation; the other two mirror it. See Gotchas.

### No issue number — find what's pending, then ask

When the user says `/acpd` with no number:

1. Run `bash .claude/skills/acpd/aacp.sh --pending` to list issue
   numbers whose `## 구현 결과` is already filled in (i.e. `/tdd2`
   finished them) but haven't been archived/deployed yet.
2. If empty: report there's nothing pending. Stop.
3. If one or more numbers: show them, ask the user to confirm
   deploying (compose the commit summary yourself from the issue's
   title / `구현 결과` content), then run the explicit-number form
   above for each confirmed issue.

## What the script does

Run from anywhere inside the target repo — it resolves the repo root
itself.

0. **Python-project verification gate**, only if `pyproject.toml`
   exists at the repo root: runs `run-ruff`, `run-pyright`,
   `run-unit-tests`, `run-regression-tests`, `run-pyright-full`, in
   that order (see "The five checks" below). Any failure aborts here —
   before any git mutation.
1. Stages `issues/issue-<#>.md` (its own edits, e.g. the `## 구현 결과` section).
2. Archives it: `git mv` to `issues/archive/YYYY/MM/DD/issue-<#>.md`.
3. `git add -u` — stages the rest of the already-tracked changes. Never touches untracked files.
4. Commits code + archiving as **one commit**, message `issue-<#>: <summary>` with the `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` trailer appended automatically — don't add it yourself.
5. `git push`.
6. Deploy — **dev only, always**; this skill never touches qa/prod, and
   never generates or scaffolds a deploy script. It just looks for one
   in the target repo, same-platform, in this order, and runs the
   first one it finds with `--env dev`:
   - `deploy.{sh,ps1,bat}` — the project's primary deploy entry point.
   - else `deploy-to-env.{sh,ps1,bat}` — an alternate name some
     projects use.
   - else neither exists: deploy is skipped (not a failure) with a
     note telling you to add one. Setting up that script is on the
     **target project**, not this skill — see Gotchas.

Fails fast (`set -e`, exit 1) with no git side effects if
`issues/issue-<#>.md` doesn't exist, or if any step-0 check fails —
check the issue number first, and don't call `acpd` on code that
hasn't already passed `/tdd2`'s own verification.

## The five checks (Python projects only)

For each of `run-ruff`, `run-pyright`, `run-unit-tests`,
`run-regression-tests`, `run-pyright-full`: if the target repo has its
own executable `./run-<name>.sh`, that runs. Otherwise this skill's
bundled default in `defaults/run-<name>.sh` runs instead — **not**
copied into the project, just invoked from the skill directory with
CWD already set to the repo root. `.bat`/`.ps1` siblings exist in
`defaults/` for a human on Windows running the equivalent by hand, and
`aacp.ps1` resolves `.ps1` project-or-default the same way — but
each of `acpd`'s own three entry scripts only ever calls its own
platform's flavor.

This is a final gate, not a substitute for `/tdd2`'s own step 5–9
verification — by the time `acpd` runs, these should already be green.
It exists so nothing broken reaches `main`/dev even if the working
tree changed after `/tdd2` finished.

`run-pyright` is scoped to `src/` (fast); `run-pyright-full` has no
path restriction (slower, whole project) — same fast/thorough split as
`run-unit-tests` vs a project's own coverage script.

Verified end-to-end (via `aacp.sh`) against a real `uv`-managed
Python project: all five defaults ran for real (ruff, pyright, and
pytest actually executed, not mocked) and the gate correctly aborted
with zero git side effects on a real pytest failure; a project with
its own `run-*.sh` overrides had every check dispatch to the project's
version instead of the default; a non-Python repo (no `pyproject.toml`)
skips step 0 entirely.

## How "pending" is detected

No separate state file. An issue counts as pending-deploy once its
`## 구현 결과` section's `**구현 완료 일시**:` line is no longer the
`(미정)` placeholder — that's the existing issue-template completion
marker, already written by `/tdd2` when it finishes. `--pending` greps
every `issues/issue-*.md` (archived ones are excluded — they live
under `issues/archive/`, a different path) for that signal.

## Gotchas

- **`aacp.ps1` and `aacp.bat` were not run in this environment — no
  PowerShell available here.** `aacp.ps1` is a careful, line-by-line
  manual port of the exercised `aacp.sh` (same steps, same guarantees)
  but hasn't been executed for real; verify it on an actual
  Windows/PowerShell host before relying on it for anything important.
  `aacp.bat` is intentionally thin — it just locates `pwsh` (preferred)
  or `powershell` on `PATH` and forwards to `aacp.ps1`, rather than
  reimplementing ~150 lines of archive/commit/push/gate logic a third
  time in raw batch. It does **not** pass `-ExecutionPolicy Bypass`; if
  your system's execution policy blocks local scripts, set it yourself
  (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`) or use
  `aacp.sh` under WSL/git-bash instead.
- **The target repo's deploy script is a per-project convention this
  skill never creates.** Deploy is step 5 of `acpd` in name only —
  it's the one step this skill deliberately doesn't implement. Setting
  up `deploy.{sh,ps1,bat}` (or `deploy-to-env.{sh,ps1,bat}`) in the
  target repo, and making it accept `--env dev`, is the target
  project's job (see the Quickstart in the `autotdd` repo's README).
  If neither exists when `aacp` reaches step 6, it prints a note and
  exits 0 — a project with no deploy automation yet doesn't fail the
  whole merge, it just doesn't deploy.
- **Commit message trailer is baked into the script.** Don't pass a
  message that already includes `Co-Authored-By` — you'll get it
  twice.
- **`git add -u` is deliberate, not `git add -A`.** Untracked files
  (scratch files, new files the issue didn't ask for) are never staged
  by this skill.
