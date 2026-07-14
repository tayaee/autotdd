@echo off
REM codexcli.bat — pass-through LLM wrapper for the `codex` CLI
REM (CONTEXT.md "LLM 래퍼"). Batch port of codexcli.sh.
REM
REM FLAGS UNVERIFIED — 실 CLI 설치 환경에서 `codex --help`로 확인 후 조정할
REM 것.
REM
REM Argument convention (shared with claudecli.bat/minimaxcli.bat/...): if
REM %1 is an existing file, its content is piped to `codex -p` on stdin;
REM otherwise every argument is passed straight through.

set "CLI=codex"

where %CLI% >nul 2>&1
if errorlevel 1 (
	echo [원인] %CLI%가 PATH에 없음 1>&2
	echo [조치] %CLI% 설치 또는 PATH 추가 1>&2
	exit /b 127
)

if not "%~1" == "" (
	if exist "%~1" (
		type "%~1" | call %CLI% -p
	) else (
		call %CLI% %*
	)
	exit /b %ERRORLEVEL%
)

call %CLI% %*
exit /b %ERRORLEVEL%
