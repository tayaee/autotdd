#!/usr/bin/env bash
# acpd — Archive issue, git Add -u, Commit, Push, Deploy (dev only).
#
# Usage:
#   aacp.sh <issue-number> <commit-summary...>   # process one issue, no prompts
#   aacp.sh --pending                             # list issue numbers ready to deploy
#
# NOTE ON NAMING: this script is named after the four steps it actually
# implements — Archive, (git) Add, Commit, Push. The fifth step, Deploy, is
# deliberately NOT this skill's own logic: each target repo is expected to
# provide its own deploy entry point (see step 5 below). This file is
# `.claude/skills/acpd/aacp.sh`; the deploy script it calls at the end is
# `<target-repo>/deploy.sh` or `<target-repo>/deploy-to-env.sh` — a
# different file this skill never generates.
#
# Preconditions: run from inside the target repo (any subdirectory). Code
# changes for the issue must already be `git add`ed — that's the hand-off
# point from /tdd2.
#
# Never touches qa/prod. Only ever deploys --env dev.
set -euo pipefail

usage() {
  echo "Usage: aacp.sh <issue-number> <commit-summary...>" >&2
  echo "       aacp.sh --pending" >&2
  exit 1
}

[ $# -ge 1 ] || usage

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --pending: an issue is "pending deploy" once tdd2 has filled in its
# `## 구현 결과` section (구현 완료 일시 is no longer the "(미정)" placeholder)
# but the issue file hasn't been archived yet. No separate state file —
# this reuses the issue template's own completion marker.
if [ "${1:-}" = "--pending" ]; then
  shopt -s nullglob
  for f in issues/issue-*.md issues/autofix-*.md; do
    if grep -q '\*\*구현 완료 일시\*\*:' "$f" \
       && ! grep -q '\*\*구현 완료 일시\*\*: *(미정)' "$f"; then
      basename "$f" .md
    fi
  done
  exit 0
fi

[ $# -ge 2 ] || usage
ISSUE_NUM="$1"
shift
SUMMARY="$*"

# Stream detection: "issue-N" / "autofix-N" / bare "N" (defaults to issue).
case "$ISSUE_NUM" in
    issue-*|autofix-*) STREAM="${ISSUE_NUM%%-*}"; N="${ISSUE_NUM#*-}" ;;
    *)                 STREAM="issue";            N="$ISSUE_NUM" ;;
esac

ISSUE_FILE="issues/${STREAM}-${N}.md"
if [ ! -f "$ISSUE_FILE" ]; then
  echo "ERROR: $ISSUE_FILE not found" >&2
  exit 1
fi

# 0. Python-project verification gate. Detected via pyproject.toml at the
# repo root. For each check, prefer the project's own ./run-<name>.sh if it
# exists (and is executable); otherwise fall back to this skill's bundled
# default in defaults/ (never copied into the project — see SKILL.md).
# Runs before any git mutation, so a failure here leaves the repo untouched.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_DIR="$SKILL_DIR/defaults"

run_check() {
  local name="$1"
  if [ -x "./${name}.sh" ]; then
    echo "--- ${name} (project script) ---"
    "./${name}.sh"
  else
    echo "--- ${name} (acpd default) ---"
    bash "$DEFAULTS_DIR/${name}.sh"
  fi
}

if [ -f pyproject.toml ]; then
  echo "Python project detected (pyproject.toml) — running verification gate before merge..."
  for chk in run-ruff run-pyright run-unit-tests run-regression-tests run-pyright-full; do
    run_check "$chk"
  done
fi

# 1. Stage the issue file's own changes (e.g. the "구현 결과" section).
git add "$ISSUE_FILE"

# 2. Archive: move to issues/archive/YYYY/MM/DD/ (git mv auto-stages the rename).
ARCHIVE_DIR="issues/archive/$(date +%Y/%m/%d)"
mkdir -p "$ARCHIVE_DIR"
git mv "$ISSUE_FILE" "$ARCHIVE_DIR/${STREAM}-${N}.md"

# 2.5. Archive this issue's __TYPE-* artifacts alongside it (code-review
# files, refix-plan, agent-stats.json — issue-47). Live artifacts only
# (this glob never reaches into issues/archive/). agent-stats.json gets
# its `archived`/`duration` fields stamped by a dedicated helper *before*
# the move, since bash has no clean JSON/ISO-8601-duration support.
shopt -s nullglob
TYPE_FILES=(issues/"${STREAM}-${N}"__TYPE-*)
shopt -u nullglob
for tf in "${TYPE_FILES[@]}"; do
  case "$tf" in
    *__TYPE-agent-stats.json)
      uv run "$DEFAULTS_DIR/agent-stats-archive.py" "$REPO_ROOT" "${STREAM}-${N}"
      ;;
  esac
  git mv "$tf" "$ARCHIVE_DIR/$(basename "$tf")"
done

# 3. Stage the rest of the already-tracked changes (never untracked files).
git add -u

# 4. Commit code + archiving as ONE commit.
COMMIT_MSG="${STREAM}-${N}: ${SUMMARY}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git commit -m "$COMMIT_MSG"

# 5. Push.
git push

# 6. Deploy — dev only, ever. This is the ONE step this skill does not
# implement itself: it's each target repo's own responsibility to provide
# a deploy entry point. Resolution order:
#   - ./deploy.sh exists  -> run it as `deploy.sh --env dev`
#   - else ./deploy-to-env.sh exists -> run it as `deploy-to-env.sh --env dev`
#   - else -> no deploy script yet; skip (not a failure) and say so.
DEPLOY_STATUS="no deploy.sh or deploy-to-env.sh found — deploy skipped"
if [ -f deploy.sh ]; then
  bash deploy.sh --env dev
  DEPLOY_STATUS="deploy.sh --env dev run"
elif [ -f deploy-to-env.sh ]; then
  bash deploy-to-env.sh --env dev
  DEPLOY_STATUS="deploy-to-env.sh --env dev run"
else
  echo "NOTE: this project has no deploy.sh or deploy-to-env.sh — skipping deploy." >&2
  echo "Add one (deploy.sh or deploy-to-env.sh, accepting --env <env>) to enable it." >&2
fi

echo "✓ acpd complete: issue-${ISSUE_NUM} archived to ${ARCHIVE_DIR}/, committed, pushed, ${DEPLOY_STATUS}."
