@echo off
rem acpd default -- log-run.bat: thin dispatcher to log-run.ps1 (PowerShell 7+ preferred,
rem Windows PowerShell fallback). 호출법은 log-run.ps1와 동일.
rem
rem 이 파일은 PowerShell 스크립트로 위임하며 자체 파싱 로직을 두지 않는다 —
rem .ps1가 없는 환경에서는 "neither pwsh nor powershell" 안내와 함께 종료한다.
setlocal
set SCRIPT_DIR=%~dp0

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -File "%SCRIPT_DIR%log-run.ps1" %*
    exit /b %ERRORLEVEL%
)

where powershell >nul 2>nul
if %ERRORLEVEL%==0 (
    powershell -NoProfile -File "%SCRIPT_DIR%log-run.ps1" %*
    exit /b %ERRORLEVEL%
)

echo ERROR: neither pwsh nor powershell found on PATH. 1>&2
echo acpd's log-run.bat needs PowerShell (7+ or Windows PowerShell) to run log-run.ps1. 1>&2
echo Alternatively, run log-run.sh under WSL/git-bash instead. 1>&2
exit /b 1
