# acpd default -- used only when the target project has no
# run-pyright.ps1 of its own. Assumes CWD is already the target repo root.
# Quick pass: type-checks src/ only. See run-pyright-full.ps1 for the whole
# project.
Write-Host "=== pyright (src only) ==="
if (Test-Path "src") {
    uv run pyright src
} else {
    uv run pyright .
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
