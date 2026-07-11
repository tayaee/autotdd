if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "[원인] uv 없음"
    Write-Output "[조치] irm https://astral.sh/uv/install.ps1 | iex"
    exit 127
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir ".claude/skills/autoqafix/role-loop.py"

uv -q run "$PyScript" --repo (Get-Location).Path --role qa @args
exit $LASTEXITCODE
