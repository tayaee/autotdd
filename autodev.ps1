# autodev launcher — same as autofix.ps1 but pinned to the `issue` stream
# (see autofix.py STREAMS / stream_to_role: `issue` → role `dev`).
# Mirrors autoqa.ps1 pattern (issue-14).
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "[원인] uv 없음"
    Write-Output "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir ".claude/skills/autoqafix/autofix.py"

uv -q run "$PyScript" --repo (Get-Location).Path --stream issue
exit $LASTEXITCODE