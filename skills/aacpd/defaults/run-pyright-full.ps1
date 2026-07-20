# aacpd default -- used only when the target project has no
# run-pyright-full.ps1 of its own. Assumes CWD is already the target repo
# root. Full pass: type-checks the whole project, unlike the src-only
# run-pyright.ps1.
Write-Host "=== pyright (full project) ==="
uv run pyright
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
