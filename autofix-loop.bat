@echo off
where uv >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [원인] uv 없음
    echo [조치] powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    pause
    exit /b 127
)

set SCRIPT_DIR=%~dp0
set PY_SCRIPT=%SCRIPT_DIR%.claude\skills\autoqafix\role-loop.py

uv -q run "%PY_SCRIPT%" --repo "%CD%" --role fix %*
set EXIT_VAL=%ERRORLEVEL%
if %EXIT_VAL% neq 0 (
    pause
)
exit /b %EXIT_VAL%
