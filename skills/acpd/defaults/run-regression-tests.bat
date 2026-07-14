@echo off
rem acpd default -- used only when the target project has no
rem run-regression-tests.bat of its own. Assumes CWD is already the target
rem repo root. Runs every regression-tests\verify-issue-*.sh (via bash) in
rem order. verify-issue-*.sh scripts are always bash, even on Windows hosts.
setlocal enabledelayedexpansion
set PASS=0
set FAIL=0
set FAILED=

for %%s in (regression-tests\verify-issue-*.sh) do (
    echo.
    bash "%%s"
    if errorlevel 1 (
        set /a FAIL+=1
        set FAILED=!FAILED! %%s
    ) else (
        set /a PASS+=1
    )
)

echo.
echo =============================
echo Regression results: PASS=%PASS% FAIL=%FAIL%
if %FAIL% gtr 0 (
    echo Failed scripts:%FAILED%
    exit /b 1
)
exit /b 0
