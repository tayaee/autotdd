@echo off
rem autofix launcher — cmd mirror of autoqa.bat (issue-14). Detects uv,
rem locates autofix.py relative to this script's directory, exec via
rem `uv -q run`. Stream defaults to autofix (see autofix.py STREAM_DEFAULT).
where uv >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [원인] uv 없음
    echo [조치] curl -LsSf https://astral.sh/uv/install.sh | sh
    pause
    exit /b 127
)

set SCRIPT_DIR=%~dp0
set PY_SCRIPT=%SCRIPT_DIR%.claude\skills\autoqafix\autofix.py

uv -q run "%PY_SCRIPT%" --repo "%CD%"
set EXIT_VAL=%ERRORLEVEL%
if %EXIT_VAL% neq 0 (
    pause
)
exit /b %EXIT_VAL%