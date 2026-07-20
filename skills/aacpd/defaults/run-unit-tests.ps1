# aacpd default -- used only when the target project has no
# run-unit-tests.ps1 of its own. Assumes CWD is already the target repo root.
uv run pytest @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
