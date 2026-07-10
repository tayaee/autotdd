@echo off
REM minimaxcli.bat — LLM wrapper that re-points the Claude CLI at the
REM MiniMax coding-plan endpoint (CONTEXT.md "LLM 래퍼"). Ported from
REM /rosenas/data/util/minimax3-claude.bat.
REM
REM Argument convention (shared with claudecli.bat): if %1 is an
REM existing file, its content is piped to `claude ... -p` on stdin;
REM otherwise every argument is passed straight through.

setlocal enabledelayedexpansion

if .%MINIMAX_API_KEY%. == .. (
	echo [원인] MINIMAX_API_KEY 환경변수가 설정되지 않았습니다. 1>&2
	echo [조치] MINIMAX_API_KEY를 설정한 뒤 다시 실행하세요. 1>&2
	exit /b 1
)

set "MODEL=MiniMax-M3"

REM msys2/git-bash path, needed by Claude Code on Windows for its own
REM bash-dependent tooling.
set MSYSTEM=UCRT64
set CHERE_INVOKING=1
set HOME=%USERPROFILE%
if not defined CLAUDE_CODE_GIT_BASH_PATH set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\usr\bin\bash.exe"

set ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic
set ANTHROPIC_AUTH_TOKEN=%MINIMAX_API_KEY%
set API_TIMEOUT_MS=3000000
set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
set ANTHROPIC_MODEL=%MODEL%
set ANTHROPIC_SMALL_FAST_MODEL=%MODEL%
set ANTHROPIC_DEFAULT_SONNET_MODEL=%MODEL%
set ANTHROPIC_DEFAULT_OPUS_MODEL=%MODEL%
set ANTHROPIC_DEFAULT_HAIKU_MODEL=%MODEL%

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
		type "%~1" | call claude --model=%MODEL% --dangerously-skip-permissions -p
	) else (
		call claude --model=%MODEL% --dangerously-skip-permissions %*
	)
	exit /b %ERRORLEVEL%
)

call claude --model=%MODEL% --dangerously-skip-permissions %*
exit /b %ERRORLEVEL%
