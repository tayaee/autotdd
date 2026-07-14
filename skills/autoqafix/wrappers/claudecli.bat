@echo off
REM claudecli.bat — LLM wrapper for the Claude Code coding plan
REM (CONTEXT.md "LLM 래퍼"). Ported from /rosenas/data/util/sonnet.bat.
REM
REM Argument convention (shared with minimaxcli.bat): if %1 is an
REM existing file, its content is piped to `claude ... -p` on stdin;
REM otherwise every argument is passed straight through.

set "MODEL=sonnet"

REM msys2/git-bash path, needed by Claude Code on Windows for its own
REM bash-dependent tooling.
set MSYSTEM=UCRT64
set CHERE_INVOKING=1
set HOME=%USERPROFILE%
if not defined CLAUDE_CODE_GIT_BASH_PATH set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe"

REM mitmproxy CA: never clobber a caller-provided NODE_EXTRA_CA_CERTS;
REM only fill it in from the default mitmproxy cert location if unset.
if not defined NODE_EXTRA_CA_CERTS (
	if exist "%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem" (
		set "NODE_EXTRA_CA_CERTS=%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem"
	)
)

REM `claude` is resolved via PATH (never hardcoded), so tests can shadow
REM it with a fake by prepending a directory to PATH.
if not "%~1" == "" (
	if exist "%~1" (
		type "%~1" | call claude --model %MODEL% --effort medium --permission-mode=bypassPermissions -p
	) else (
		call claude --model %MODEL% --effort medium --permission-mode=bypassPermissions %*
	)
	exit /b %ERRORLEVEL%
)

call claude --model %MODEL% --effort medium --permission-mode=bypassPermissions %*
exit /b %ERRORLEVEL%
