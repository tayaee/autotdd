# aacpd default -- used only when the target project has no
# run-ruff.ps1 of its own. Assumes CWD is already the target repo root.
Write-Host "=== ruff check --fix ==="
uv run ruff check --fix
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
