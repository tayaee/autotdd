@echo off
rem aacpd -- thin dispatcher to aacp.ps1.
rem
rem Batch is a poor fit for the archive/commit/push/gate logic (multi-line
rem commit messages, regex-ish state detection, the 5-check Python gate) --
rem duplicating aacp.sh's ~150 lines a third time in raw batch would be a
rem maintenance and correctness risk for no real benefit, since PowerShell
rem ships on every supported Windows version. This wrapper just forwards to
rem the real (PowerShell) implementation: prefers pwsh (PowerShell 7+) and
rem falls back to Windows PowerShell (powershell.exe) if pwsh isn't on PATH.
rem
rem NOTE: this does not pass -ExecutionPolicy Bypass. If your system's
rem PowerShell execution policy blocks local scripts, either run
rem `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` yourself first, or
rem run aacp.sh under WSL/git-bash instead.
setlocal
set SCRIPT_DIR=%~dp0

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -File "%SCRIPT_DIR%aacp.ps1" %*
    exit /b %ERRORLEVEL%
)

where powershell >nul 2>nul
if %ERRORLEVEL%==0 (
    powershell -NoProfile -File "%SCRIPT_DIR%aacp.ps1" %*
    exit /b %ERRORLEVEL%
)

echo ERROR: neither pwsh nor powershell found on PATH. 1>&2
echo aacpd's aacp.bat needs PowerShell (7+ or Windows PowerShell) to run aacp.ps1. 1>&2
echo Alternatively, run aacp.sh under WSL/git-bash. 1>&2
exit /b 1
