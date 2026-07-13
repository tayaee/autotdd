---
name: tdd2
description: Issue-driven TDD for a single local issue file (issues/issue-#.md) — red-green-refactor, then write regression-tests/verify-issue-#.sh, run ruff+pyright+pytest+regression scripts (project's own run-*.sh if present, else this package's defaults), do UI verification when the issue calls for it, update the issue's 구현 결과 section, stop at git add. With no issue number, detects an in-progress issue to resume or picks the smallest pending one to start, and asks first. Use when the user says "/tdd2", "tdd2 #", or asks to implement a numbered local issue test-first.
---

# tdd2 — issue-driven TDD, local-file SDLC

**Dependency**: the red→green→refactor discipline itself (test at
agreed seams, no implementation-coupled or tautological tests, one
slice at a time) is Matt Pocock's `tdd` skill — this skill assumes
`tdd` (`~/.claude/skills/tdd/`) is installed and wraps it with this
project family's local-file SDLC: issues live in `issues/issue-#.md`
(never GitHub/GitLab), and implementation stops at `git add` — merging
is a separate step, handled by the `acpd` skill (directly, or chained
per-issue by `/autotdd`, which also checks that `tdd` is present
before starting — see that skill if `tdd` turns out to be missing).

No script of its own. For the `run-ruff` / `run-pyright` /
`run-unit-tests` / `run-regression-tests` / `run-pyright-full` checks
in the procedure below, this skill shares `acpd`'s resolution
convention and bundled defaults (`../acpd/defaults/`, a sibling skill
directory — both ship together in this package) rather than
duplicating them.

## Stream conventions

파일명 규약의 단일 정본은 `docs/spec/spec-issue-filenames.md`다
(문법 상세·엄격성 규칙·가드의 정확한 패턴 표는 그 문서를 따른다). 요약:

- **문법**: `<stream>-<N>[-<slug>][__<KEY>-<value>]*.md` — stream은
  `issue`/`autofix`, 슬러그는 영문자로 시작하는 소문자 kebab(사람용
  라벨, 판정 불관여), KEY는 대문자 `TYPE`/`STATE`/`BY`만(이 순서).
- **판정 규칙**: `__TYPE-`도 `__STATE-`도 없으면 pending(작업 대상).
  하나라도 있으면 제외 — `__STATE-later`/`__STATE-manual`/
  `__STATE-agent-failed`는 파킹(사람이 태그를 지우면 승격),
  `__TYPE-*`는 산출물(영원히 작업 아님).
- **ID 추출**: 정규식 `^(issue|autofix)-([0-9]+)` — 슬러그·태그가
  있어도 번호는 이걸로 뽑는다.
- **예약 슬러그 가드**: 태그 없는 파일이 구(v1) 규약 구조에 해당하면
  (spec 문서의 가드 절 — 정확·꼬리 매치 패턴 표 참조) pending으로
  취급하지 말고 "harness-project의 `upgrade-issue-filenames.sh`를
  실행하라"는 안내와 함께 중단한다.
- **Regression script path**: `regression-tests/verify-<stream>-<N>.sh`
  (e.g., `verify-issue-22.sh`, `verify-autofix-3.sh`) — 슬러그·태그는
  스크립트명에 포함하지 않는다.

## Argument parsing

`tdd2 issue-280`, `tdd2 issue 280`, `tdd2 280` are all the same thing:
extract the digits from the first token, normalize to `#`, then resolve
the file: `issues/issue-#.md` if it exists, otherwise the unique
tag-less `issues/issue-#-<slug>.md`. 태그 없는 후보가 같은 번호에 2개
이상이면 중복 오류로 중단.

## No issue number given — resume or pick, then ask

Run when the user says `/tdd2` with no number:

1. **Look for an in-progress issue** — one whose `## 구현 결과` is still
   the `(미정)` placeholder but that already has a draft
   `regression-tests/verify-issue-#.sh` (written in step 4 below,
   before an issue is finished — its presence means work started but
   didn't reach completion):

   ```bash
   for f in issues/issue-*.md; do
     base=$(basename "$f" .md)
     [[ "$base" == *__* ]] && continue   # 태그 파일(산출물·파킹) 제외
     rest="${base#issue-}"; slug="${rest#*-}"; [ "$slug" = "$rest" ] && slug=""
     case "$slug" in later|manual|agent-failed)
       echo "구 규약 파일 감지: $f — harness-project의 upgrade-issue-filenames.sh 실행 요망" >&2; exit 1 ;;
     esac   # 산출물 꼬리 패턴 등 나머지 가드는 spec 문서의 표를 적용
     n="${rest%%-*}"
     if grep -q '\*\*구현 완료 일시\*\*: *(미정)' "$f" \
        && [ -f "regression-tests/verify-issue-${n}.sh" ]; then
       echo "$n"
     fi
   done
   ```

   Found one (or more — take the smallest) → ask: "issue #N looks
   in-progress — resume it?"

2. **Nothing in-progress** → pick the smallest-numbered not-yet-started
   issue:

   ```bash
   for f in issues/issue-*.md; do
     base=$(basename "$f" .md)
     [[ "$base" == *__* ]] && continue   # 태그 파일(산출물·파킹) 제외 — 가드는 위와 동일
     n=$(echo "$base" | sed -E 's/^issue-([0-9]+).*/\1/')
     grep -q '\*\*구현 완료 일시\*\*: *(미정)' "$f" \
       && [ ! -f "regression-tests/verify-issue-${n}.sh" ] \
       && echo "$n"
   done | sort -n | head -1
   ```

   Ask: "no issue in progress — start with issue #N (smallest
   pending)?"

3. No candidates either way → report `issues/` has nothing left to do.

This is the only place `tdd2` asks anything. Given an explicit issue
number, it just starts — no confirmation.

## Execution mode

**Stop at `git add`.** Implement, verify, update the issue file, stage
everything — then stop. Do not commit, push, archive, or deploy. A
human (or the `acpd` skill, or `/autotdd` looping both) takes it from
there. This boundary matters for `/autotdd`: each issue must be fully
merged (`tdd2` → `acpd`) before the next one starts, so a mid-batch
failure has an unambiguous line between what's live and what isn't.

## Procedure

1. Read `issues/issue-#.md` to understand what's being built.

   **UI-touching test** (the single definition — used here, in step 10,
   and by `/autotdd`'s pre-loop check): the issue body references
   `templates/` paths or `.html`/`.css`/`.js` files, **and** at least
   one requirement in `## 요구사항` describes user-visible browser
   behaviour. A file-extension match alone does not qualify — backend
   Node scripts, build configs, and email templates are not UI. When
   in doubt, ask: does a user see or click this in a browser?

   If the issue is UI-touching and the `agent-browser` **skill**
   (source: `vercel-labs/agent-browser`) is not installed (not in the
   Available Skills listing and no `agent-browser/SKILL.md` under
   `~/.claude/skills/` or this repo's `.claude/skills/`), warn once:

   > ⚠️ This issue touches UI files but the `agent-browser` skill is
   > not installed. Step 10 (UI verification) will pause on a manual
   > checklist, then auto-install it as the fallback. To skip the
   > pause, install it now:
   > `npx skills add vercel-labs/agent-browser -g -y`

   Then continue — `tdd2` does not block on this. The warning is
   informational; under `/autotdd` the pre-loop check installs it
   before this step is ever reached.

2. Implement via red→green→refactor: write the failing test first,
   then only enough code to pass it, at pre-agreed seams (the public
   boundary you test at — never internals). No implementation-coupled
   tests (mocking internal collaborators, testing private methods), no
   tautological assertions (expected value computed the same way the
   code computes it) — expected values come from an independent source
   of truth. Work in vertical slices: one seam, one test, one minimal
   implementation, repeat. Refactoring happens at review time, not
   inside this loop.
3. **DB DDL changes only**: run `./upgrade_db.sh --env dev`. (qa/prod
   DDL is applied by a human separately — never touch those here.)
4. Write `regression-tests/verify-issue-#.sh`: mechanical checks for
   *this issue's* acceptance criteria only (grep for required
   functions/CSS/HTML, check migration files exist, etc). Do **not**
   put `ruff check`, `pyright`, or the full `pytest` suite in this
   script — those run separately in steps 5–8. A targeted
   `uv run pytest tests/some_file.py` for this issue's own test file is
   fine to include. `chmod +x` it. (This file's existence is also what
   the no-arg resume-detection above looks for.)
5. **Python projects only** (repo has `pyproject.toml`): run `run-ruff`
   and `run-pyright`. For each, prefer the project's own
   `./run-<name>.sh` if present; otherwise use this package's bundled
   default at `../acpd/defaults/run-<name>.sh` (relative to this skill
   directory — invoke with `bash`, CWD at the repo root; never copy it
   into the project). `run-pyright` is scoped to `src/`, fast.
   Failure → fix code, restart from 5.

   **coding-stats 계측**: 시작 시 `git rev-parse HEAD`를 `<시작HEAD>`로
   기록한다 (Step 11의 loc_added 산출용). ruff/pyright 각각 실패해 "restart from 5"할
   때마다 실행 세션이 자기 작업 컨텍스트 안에서 카운터(실패 횟수)를 증가시킨다
   (파일 I/O 없음). pytest/회귀 스크립트는 계측하지 않는다.
6. `uv run python -m compileall . -q`. Failure → fix code, restart from 5.
7. `run-unit-tests` (full suite) — same project-or-default resolution
   as step 5. Failure → fix code, restart from 5.
8. Run `./regression-tests/verify-issue-#.sh` directly (this is the
   issue-specific script from step 4, not the `run-regression-tests`
   wrapper). Exit 0 → continue. Non-zero → fix implementation, restart
   from 5.
9. `run-regression-tests` — same project-or-default resolution as step
   5; runs every *other* existing `regression-tests/verify-issue-*.sh`
   in order.
   - All pass → continue.
   - A failure is either: (a) a real bug in the new code — fix and
     restart from 5; or (b) that script's own criteria are now
     obsolete because this issue intentionally changed behavior —
     update that script, then write
     `regression-tests/verify-issue-<old#>.conflict-with-<this#>.md`
     documenting what changed and why (a human reviews and resolves
     that file later; stage it with the rest).
   - **Python projects only**: also run `run-pyright-full` (whole
     project, no path restriction — slower than step 5's `run-pyright`)
     before moving on. Same failure handling as above.
10. **UI verification** — triggered when the issue has a `### UI 검증`
    section, **or** when the issue is UI-touching per the test defined
    in step 1 (extension match *plus* user-visible browser behaviour —
    never on a file-extension match alone).

    **If UI-touching but no `### UI 검증` section exists:** derive a
    minimal checklist from the issue's `## 요구사항` section — one
    check per user-visible behaviour listed — and insert the section
    into `issues/issue-#.md` now (before verifying). Stage the updated
    file with the rest at step 12.

    Then, with a checklist in hand (explicit or derived):
    - `agent-browser` skill installed → drive the golden path and each
      checklist item directly; confirm no console errors.
    - Not installed → print the checklist and ask the user to check it.
      Wait up to 2 minutes (a response interrupts the wait and its
      content is used to continue). No response after 2 minutes → post
      a 30-second countdown warning, wait 30s more, then install the
      skill (`npx skills add vercel-labs/agent-browser -g -y`) and run
      the automated verification with it. If the installation fails,
      stop and report.
    - This step is never skipped — only the *method* varies.
      **Exception: when running as part of `/autotdd`**, that skill's
      fully-automatic mode forbids waiting on a human — its pre-loop
      check installs `agent-browser` up front, so this branch normally
      never arises there; if it somehow does, stop and report instead
      of prompting-then-waiting.
11. Update `issues/issue-#.md`'s `## 구현 결과` section: completion
    timestamp (ISO 8601), changed files, deviation from plan (or
    "없음"), and the verify result (this script's pass/fail +
    regression suite status).

    **coding-stats.json 최초 생성**: 위 갱신 직전, `issues/issue-<#N>__TYPE-coding-stats.json`
    파일을 생성 또는 갱신한다:
    ```json
    {
      "issue": <이슈번호>,
      "coders": {
        "<base명>": {
          "model": "<버전 포함 모델명>",
          "mvp": {
            "ts": "<ISO8601>",
            "loc_added": <loc_added 수치>,
            "static_analysis_failures": {
              "ruff": <ruff 실패 횟수>,
              "pyright": <pyright 실패 횟수>
            }
          }
        }
      }
    }
    ```
    - `loc_added`는 `<시작HEAD>..HEAD` 전 파일의 `git diff --numstat` added 합 (삭제·바이너리 제외).
    - `ruff` / `pyright` 실패 횟수는 Step 5에서 세션이 카운트한 값이며, 해당 도구가 프로젝트 미지원(pyproject.toml 없음 등)으로 실행 안 된 경우 `null`로 기록한다.
    - 파일이 이미 존재하면 `mvp` 섹션만 덮어쓰고 기존 `review_outcome` 섹션이 존재할 경우 보존한다.
12. `git add` everything: migration files, code, the updated issue
    file, any `.conflict-with-` notes.
13. **Stop.** Report what was implemented and that it's ready for
    `acpd #` (or, mid-batch under `/autotdd`, that it will be chained
    automatically).

Both a human and an agent use the same completion bar:
`verify-issue-#.sh` exits 0 *and* every existing regression script
still passes.
