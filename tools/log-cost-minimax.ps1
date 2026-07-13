# uv run wrapper -- log-cost-minimax.py declares a PEP 723 inline dependency on
# pydantic, so it must be run via `uv run`, not plain `python`.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
uv run (Join-Path $ScriptDir "log-cost-minimax.py") @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
