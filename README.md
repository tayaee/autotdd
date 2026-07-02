# autotdd

Three Claude Code skills implementing an issue-driven, local-file TDD
workflow (no GitHub/GitLab — issues are `issues/issue-#.md`). The name
is literal: **tdd** (via `tdd2`, which extends Matt Pocock's `tdd`
skill to point at local issue files) **+ auto**mating everything after
it (`acpd`: archive, commit, push, deploy).

- **`tdd2`** — implement one issue, test-first, stop at `git add`.
  Depends on Matt Pocock's `tdd` skill for the actual red→green→refactor
  discipline. No number given → detect an in-progress issue to resume,
  or pick the smallest pending one to start; asks once before either.
- **`acpd`** — archive the issue, commit code+archive together, push,
  deploy to dev (the target repo's own `deploy.{sh,ps1,bat} --env dev`).
  No number given → find what's pending and ask before processing it.
- **`autotdd`** — fully-automatic: `tdd2` then `acpd` per issue, one
  issue fully finished before the next starts, never batched, never
  prompts mid-run. With no numbers, lists everything left in `issues/`
  and asks once whether to run through all of it. Also checks that
  `tdd` is installed before starting anything — see its `SKILL.md`.

See each skill's `SKILL.md` for full behavior. `acpd/deploy.{sh,ps1,bat}`
are the only backing scripts (`tdd2` and `autotdd` are pure
orchestration/procedure, no script needed — `tdd2`'s verification steps
reuse `acpd`'s defaults, see below, rather than duplicating them).
`deploy.sh` is canonical and the most exercised; `deploy.ps1` is a
line-by-line port for hosts without bash/WSL; `deploy.bat` just forwards
to `deploy.ps1`.

For Python projects (`pyproject.toml` present), both `tdd2` (during
implementation) and `acpd` (as a final gate before merge) run
`run-ruff` / `run-pyright` / `run-unit-tests` / `run-regression-tests`
/ `run-pyright-full`. Each resolves independently: the target repo's
own `./run-<name>.sh` if it has one, otherwise the default bundled at
`acpd/defaults/run-<name>.{sh,bat,ps1}` (invoked from there, never
copied into the project). `deploy.sh` only ever calls the `.sh`
defaults and `deploy.ps1` only ever calls the `.ps1` defaults; `.bat`
defaults exist for a human running a check by hand on Windows.

## Install

Clone this repo somewhere on disk, then symlink (or copy) the skill
directories into a project's `.claude/skills/`, or into
`~/.claude/skills/` for global availability:

```bash
git clone https://github.com/tayaee/autotdd.git ~/git/autotdd

ln -s ~/git/autotdd/.claude/skills/tdd2    ~/.claude/skills/tdd2
ln -s ~/git/autotdd/.claude/skills/acpd    ~/.claude/skills/acpd
ln -s ~/git/autotdd/.claude/skills/autotdd ~/.claude/skills/autotdd
```

To make it project-scoped instead (only visible while working inside
one repo), symlink into that repo's `.claude/skills/` instead of
`~/.claude/skills/` — Claude Code discovers skills from any nested
`.claude/skills/` directory.

`tdd2` also requires Matt Pocock's `tdd` skill to already be installed
separately (e.g. at `~/.claude/skills/tdd/`) — `autotdd` checks for it
and tells you if it's missing, but doesn't install it for you (this
package doesn't know where you got it from).

## Conventions these skills assume in the target repo

- `issues/issue-#.md` — active issues, ending in a `## 구현 결과`
  section whose `**구현 완료 일시**:` field is `(미정)` until `tdd2`
  fills it in on completion. That field is the only state signal these
  skills rely on — no separate state file.
- `issues/archive/YYYY/MM/DD/issue-#.md` — where `acpd` moves a
  finished issue on merge.
- `regression-tests/verify-issue-#.sh` — per-issue acceptance script,
  written by `tdd2` before it finishes (its existence, combined with an
  unfinished issue, is what `tdd2`'s resume-detection looks for).
- `deploy.{sh,ps1,bat} --env <env>` — the deploy entry point. If
  missing, `acpd` generates one that dispatches to a legacy
  `deploy-to-<env>.{sh,ps1,bat}` if present, or stubs out with a TODO.
