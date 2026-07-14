# minimaxcli.ps1 — LLM wrapper that re-points the Claude CLI at the
# MiniMax coding-plan endpoint (CONTEXT.md "LLM 래퍼"). PowerShell port of
# minimaxcli.sh / the reference implementation at
# /rosenas/data/util/minimax3-claude.bat.
#
# NOTE: this script has not been executed in this environment (no
# PowerShell available under WSL) — verified by existence + grep for the
# key invocation strings only. Treat as a careful manual port of the
# exercised minimaxcli.sh until run for real on a Windows/PowerShell host.
#
# Argument convention (shared with claudecli.ps1): if the first argument
# is an existing file, its content is piped to `claude ... -p` on stdin;
# otherwise every argument is passed straight through.

if (-not $env:MINIMAX_API_KEY) {
    Write-Error "[원인] MINIMAX_API_KEY 환경변수가 설정되지 않았습니다."
    Write-Error "[조치] MINIMAX_API_KEY를 설정한 뒤 다시 실행하세요."
    exit 1
}

$Model = "MiniMax-M3"

$env:ANTHROPIC_BASE_URL = "https://api.minimax.io/anthropic"
$env:ANTHROPIC_AUTH_TOKEN = $env:MINIMAX_API_KEY
$env:API_TIMEOUT_MS = "3000000"
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
$env:ANTHROPIC_MODEL = $Model
$env:ANTHROPIC_SMALL_FAST_MODEL = $Model
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Model
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $Model

# mitmproxy CA: never clobber a caller-provided NODE_EXTRA_CA_CERTS; only
# fill it in from the default mitmproxy cert location if unset.
if (-not $env:NODE_EXTRA_CA_CERTS) {
    $mitmCert = Join-Path $env:USERPROFILE ".mitmproxy\mitmproxy-ca-cert.pem"
    if (Test-Path $mitmCert) {
        $env:NODE_EXTRA_CA_CERTS = $mitmCert
    }
}

# `claude` is resolved via PATH (never hardcoded), so tests can shadow it
# with a fake by prepending a directory to PATH.
if ($args.Count -ge 1 -and (Test-Path $args[0] -PathType Leaf)) {
    Get-Content $args[0] -Raw | claude --model=$Model --dangerously-skip-permissions -p
} else {
    claude --model=$Model --dangerously-skip-permissions @args
}
exit $LASTEXITCODE
