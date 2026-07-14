# antigravitycli.ps1 — pass-through LLM wrapper for the `antigravity` CLI
# (CONTEXT.md "LLM 래퍼"). PowerShell port of antigravitycli.sh.
#
# FLAGS UNVERIFIED — 실 CLI 설치 환경에서 `antigravity --help`로 확인 후
# 조정할 것. NOTE: this script has not been executed in this environment
# (no PowerShell, no `antigravity` CLI available under WSL) — verified by
# existence + grep for "antigravity" only.
#
# Argument convention (shared with claudecli.ps1/minimaxcli.ps1/...): if
# the first argument is an existing file, its content is piped to
# `antigravity -p` on stdin; otherwise every argument is passed straight
# through.

$CliName = "antigravity"

if (-not (Get-Command $CliName -ErrorAction SilentlyContinue)) {
    Write-Error "[원인] $CliName가 PATH에 없음"
    Write-Error "[조치] $CliName 설치 또는 PATH 추가"
    exit 127
}

if ($args.Count -ge 1 -and (Test-Path $args[0] -PathType Leaf)) {
    Get-Content $args[0] -Raw | & $CliName -p
} else {
    & $CliName @args
}
exit $LASTEXITCODE
