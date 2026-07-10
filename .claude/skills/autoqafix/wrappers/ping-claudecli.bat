@echo off
rem ping-claudecli.bat -- thin dispatcher to ping-claudecli.ps1.
rem
rem Batch has no reliable built-in per-process timeout/kill primitive, so
rem the timeout+response-check logic lives in ping-claudecli.ps1 (PowerShell
rem ships on every supported Windows version). This wrapper just forwards
rem to it: prefers pwsh (PowerShell 7+), falls back to Windows PowerShell.
rem
rem NOTE: this does not pass -ExecutionPolicy Bypass. If your system's
rem PowerShell execution policy blocks local scripts, either run
rem `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` yourself first,
rem or run ping-claudecli.sh under WSL/git-bash instead.
setlocal
set SCRIPT_DIR=%~dp0

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -File "%SCRIPT_DIR%ping-claudecli.ps1" %*
    exit /b %ERRORLEVEL%
)

where powershell >nul 2>nul
if %ERRORLEVEL%==0 (
    powershell -NoProfile -File "%SCRIPT_DIR%ping-claudecli.ps1" %*
    exit /b %ERRORLEVEL%
)

echo ERROR: neither pwsh nor powershell found on PATH. 1>&2
echo ping-claudecli.bat needs PowerShell (7+ or Windows PowerShell) to run ping-claudecli.ps1. 1>&2
echo Alternatively, run ping-claudecli.sh under WSL/git-bash. 1>&2
exit /b 1
