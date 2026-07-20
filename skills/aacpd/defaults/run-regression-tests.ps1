# aacpd default -- used only when the target project has no
# run-regression-tests.ps1 of its own. Assumes CWD is already the target
# repo root. Runs every regression-tests/verify-issue-*.sh (via bash) in
# order. verify-issue-*.sh scripts are always bash, even on Windows hosts.
$pass = 0
$fail = 0
$failed = @()

Get-ChildItem -Path "regression-tests" -Filter "verify-issue-*.sh" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ""
    bash $_.FullName
    if ($LASTEXITCODE -ne 0) {
        $fail++
        $failed += $_.Name
    } else {
        $pass++
    }
}

Write-Host ""
Write-Host "============================="
Write-Host "Regression results: PASS=$pass FAIL=$fail"
if ($fail -gt 0) {
    Write-Host "Failed scripts:"
    $failed | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
exit 0
