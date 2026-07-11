# autofix launcher — PowerShell mirror of autoqa.ps1 (issue-14). Detects
# uv, locates autofix.py relative to this script's directory, exec via
# `uv -q run`. Stream defaults to autofix (see autofix.py STREAM_DEFAULT).
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "[원인] uv 없음"
    Write-Output "[조치] irm https://astral.sh/uv/install.ps1 | iex"
    exit 127
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir ".claude/skills/autoqafix/autofix.py"

uv -q run "$PyScript" --repo (Get-Location).Path
exit $LASTEXITCODE