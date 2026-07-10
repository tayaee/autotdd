# claudecli.ps1 — LLM wrapper for the Claude Code coding plan
# (CONTEXT.md "LLM 래퍼"). PowerShell port of claudecli.sh / the reference
# implementation at /rosenas/data/util/sonnet.bat.
#
# NOTE: this script has not been executed in this environment (no
# PowerShell available under WSL) — verified by existence + grep for the
# key invocation strings only. Treat as a careful manual port of the
# exercised claudecli.sh until run for real on a Windows/PowerShell host.
#
# Argument convention (shared with minimaxcli.ps1): if the first argument
# is an existing file, its content is piped to `claude ... -p` on stdin;
# otherwise every argument is passed straight through.

$Model = "sonnet"

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
    Get-Content $args[0] -Raw | claude --model $Model --effort medium --permission-mode=bypassPermissions -p
} else {
    claude --model $Model --effort medium --permission-mode=bypassPermissions @args
}
exit $LASTEXITCODE
