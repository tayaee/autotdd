@echo off
rem autodev launcher — same as autofix.bat but pinned to the `issue` stream
rem (see autofix.py STREAMS / stream_to_role: `issue` → role `dev`).
rem Mirrors autoqa.bat pattern (issue-14).
where uv >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [원인] uv 없음
    echo [조치] curl -LsSf https://astral.sh/uv/install.sh | sh
    pause
    exit /b 127
)

set SCRIPT_DIR=%~dp0
set PY_SCRIPT=%SCRIPT_DIR%.claude\skills\autoqafix\autofix.py

uv -q run "%PY_SCRIPT%" --repo "%CD%" --stream issue
set EXIT_VAL=%ERRORLEVEL%
if %EXIT_VAL% neq 0 (
    pause
)
exit /b %EXIT_VAL%