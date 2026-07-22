# aacpd -- Archive issue, git Add -u, Commit, Push, Deploy (dev only).
#
# Usage:
#   aacp.ps1 <issue-number> <commit-summary...>   # process one issue, no prompts
#   aacp.ps1 --pending                             # list issue numbers ready to deploy
#
# Native PowerShell port of aacp.sh, for hosts without bash/WSL. Same
# steps, same guarantees (fails before any git mutation, never touches
# qa/prod, only ever --env dev). See aacp.sh for the canonical,
# most-exercised implementation and full commentary; this file mirrors it.
#
# NOTE ON NAMING: this script is named after the four steps it actually
# implements -- Archive, (git) Add, Commit, Push. The fifth step, Deploy, is
# deliberately NOT this skill's own logic: each target repo is expected to
# provide its own deploy entry point (see step 5 below). This file is
# `.claude/skills/aacpd/aacp.ps1`; the deploy script it calls at the end is
# `<target-repo>/deploy-to-dev.ps1` or `<target-repo>/deploy.ps1` -- a
# different file this skill never generates.

$ErrorActionPreference = "Stop"

function Show-Usage {
    Write-Host "Usage: aacp.ps1 <issue-number> <commit-summary...>"
    Write-Host "       aacp.ps1 --pending"
    exit 1
}

if ($args.Count -lt 1) { Show-Usage }

$RepoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $RepoRoot

# --pending: an issue is "pending deploy" once tdd2 has filled in its
# `## 구현 결과` section (구현 완료 일시 is no longer the "(미정)" placeholder)
# but the issue file hasn't been archived yet. No separate state file --
# this reuses the issue template's own completion marker.
if ($args[0] -eq "--pending") {
    Get-ChildItem -Path "issues" -Filter "issue-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match '\*\*구현 완료 일시\*\*:' -and $content -notmatch '\*\*구현 완료 일시\*\*:\s*\(미정\)') {
            $_.BaseName -replace '^issue-', ''
        }
    }
    exit 0
}

if ($args.Count -lt 2) { Show-Usage }
$IssueNum = $args[0]
$Summary = ($args[1..($args.Count - 1)] -join ' ')

$IssueFile = "issues/issue-$IssueNum.md"
if (-not (Test-Path $IssueFile -PathType Leaf)) {
    Write-Host "ERROR: $IssueFile not found"
    exit 1
}

# 0. Python-project verification gate. Detected via pyproject.toml at the
# repo root. For each check, prefer the project's own .\run-<name>.ps1 if
# it exists; otherwise fall back to this skill's bundled default in
# defaults\ (never copied into the project -- see SKILL.md). Runs before
# any git mutation, so a failure here leaves the repo untouched.
$SkillDir = Split-Path -Parent $PSCommandPath
$DefaultsDir = Join-Path $SkillDir "defaults"

function Invoke-Check {
    param([string]$Name)
    $projectScript = ".\$Name.ps1"
    if (Test-Path $projectScript -PathType Leaf) {
        Write-Host "--- $Name (project script) ---"
        & $projectScript
    } else {
        Write-Host "--- $Name (aacpd default) ---"
        & (Join-Path $DefaultsDir "$Name.ps1")
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: $Name failed (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

if (Test-Path "pyproject.toml" -PathType Leaf) {
    Write-Host "Python project detected (pyproject.toml) -- running verification gate before merge..."
    foreach ($chk in @("run-ruff", "run-pyright", "run-unit-tests", "run-regression-tests", "run-pyright-full")) {
        Invoke-Check $chk
    }
}

# 1. Stage the issue file's own changes (e.g. the "구현 결과" section).
git add $IssueFile

# 2. Archive: move to issues/archive/YYYY/MM/DD/ (git mv auto-stages the rename).
$ArchiveDir = "issues/archive/$(Get-Date -Format 'yyyy/MM/dd')"
New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null
git mv $IssueFile "$ArchiveDir/issue-$IssueNum.md"

# 2.5. Archive this issue's output artifacts alongside it (code-review
# files, refix-plan, agent-stats.json -- issue-47, v3 marker rename).
# Live artifacts only (Get-ChildItem here is non-recursive, so it never
# reaches into issues/archive/). agent-stats.json gets its
# `archived`/`duration` fields stamped by a dedicated helper *before*
# the move.
$TypeFiles = Get-ChildItem -Path "issues" -Filter "issue-$IssueNum`__code-review-by-*" -File -ErrorAction SilentlyContinue
$TypeFiles += Get-ChildItem -Path "issues" -Filter "issue-$IssueNum`__refix-plan.md" -File -ErrorAction SilentlyContinue
$TypeFiles += Get-ChildItem -Path "issues" -Filter "issue-$IssueNum`__agent-stats.json" -File -ErrorAction SilentlyContinue
foreach ($tf in $TypeFiles) {
    if ($tf.Name -like "*__agent-stats.json") {
        $LogCostSummary = Join-Path $RepoRoot "tools/log-cost-summary.py"
        if (Test-Path $LogCostSummary) {
            uv run $LogCostSummary $RepoRoot "issue-$IssueNum"
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        uv run (Join-Path $DefaultsDir "agent-stats-archive.py") $RepoRoot "issue-$IssueNum"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    git mv $tf.FullName "$ArchiveDir/$($tf.Name)"
}

# 3. Stage the rest of the already-tracked changes (never untracked files).
git add -u

# 4. Commit code + archiving as ONE commit.
$CommitMsg = "issue-${IssueNum}: $Summary`n`nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git commit -m $CommitMsg

# 5. Push.
git push

# 6. Deploy -- dev only, ever. This is the ONE step this skill does not
# implement itself: it's each target repo's own responsibility to provide
# a deploy entry point. Resolution order:
#   - .\deploy-to-dev.ps1 exists -> run it with no arguments (already
#     env-specific, takes no --env flag)
#   - else .\deploy.ps1 exists -> run it as `deploy.ps1 --env dev`
#   - else -> no deploy script yet; skip (not a failure) and say so.
$DeployStatus = "no deploy-to-dev.ps1 or deploy.ps1 found -- deploy skipped"
if (Test-Path "deploy-to-dev.ps1" -PathType Leaf) {
    & ".\deploy-to-dev.ps1"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $DeployStatus = "deploy-to-dev.ps1 run"
} elseif (Test-Path "deploy.ps1" -PathType Leaf) {
    & ".\deploy.ps1" --env dev
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $DeployStatus = "deploy.ps1 --env dev run"
} else {
    Write-Warning "this project has no deploy-to-dev.ps1 or deploy.ps1 -- skipping deploy."
    Write-Warning "Add one (deploy-to-dev.ps1, or deploy.ps1 accepting --env <env>) to enable it."
}

Write-Host "✓ aacpd complete: issue-$IssueNum archived to $ArchiveDir/, committed, pushed, $DeployStatus."
