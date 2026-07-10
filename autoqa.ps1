if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "[원인] uv 없음"
    Write-Output "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir ".claude/skills/autoqafix/autoqa.py"

uv -q run "$PyScript" --repo (Get-Location).Path
exit $LASTEXITCODE
