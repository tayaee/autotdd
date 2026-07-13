# acpd default -- log-run.ps1: PowerShell port of log-run.sh.
# 호출법: log-run.ps1 <이슈번호> <tool명> <실제 스크립트> [인자...]
# .sh와 동일한 JSONL 라인 포맷·파싱 규칙을 따른다.
#
# ruff    : `Found N errors (M fixed, ...)` + E999 라인 수
# pyright : `X errors, Y warnings ...` 의 X
# 파싱 실패 시 errors/fixed/syntax_errors는 null로 기록하되 라인은 남긴다.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)] [int]$IssueNumber,
    [Parameter(Mandatory = $true, Position = 1)] [string]$Tool,
    [Parameter(Mandatory = $true, Position = 2)] [string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args
)

$ErrorActionPreference = "Continue"

$IssuesDir = "issues"
if (-not (Test-Path $IssuesDir)) {
    Write-Error "ERROR: $IssuesDir 디렉토리가 없습니다 — repo 루트에서 실행하세요"
    exit 64
}
$Jsonl = "$IssuesDir/issue-${IssueNumber}__TYPE-coder-stats.jsonl"
$Ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# 실제 스크립트 실행 — stdout+stderr 캡처
$OutFile = [System.IO.Path]::GetTempFileName()
$ErrFile = [System.IO.Path]::GetTempFileName()

& $Script @Args *> $OutFile 2> $ErrFile
$ExitCode = $LASTEXITCODE
if (-not $ExitCode) { $ExitCode = 0 }

$Combined = (Get-Content $OutFile -Raw -Encoding UTF8) + "`n" + (Get-Content $ErrFile -Raw -Encoding UTF8)

# 사용자 출력 통과
Get-Content $OutFile
if ($Host.Name -ne "Default") {
    $errLines = Get-Content $ErrFile
    foreach ($line in $errLines) { Write-Error $line }
}

# 파싱
function Parse-Ruff($text) {
    $err = $null; $fix = $null; $syn = 0
    $lines = $text -split "`n"
    # E999 라인 수
    $syn = ($lines | Where-Object { $_ -match '\bE999\b' }).Count
    # "Found N errors (M fixed, ...)"
    $foundLine = $lines | Where-Object { $_ -match 'Found \d+ errors?' } | Select-Object -First 1
    if ($foundLine) {
        if ($foundLine -match 'Found (\d+) errors?') { $err = [int]$Matches[1] }
        if ($foundLine -match '\((\d+) fixed')       { $fix = [int]$Matches[1] }
    }
    return @{ errors = $err; fixed = $fix; syntax_errors = $syn }
}

function Parse-Pyright($text) {
    $err = $null
    $line = $text -split "`n" | Where-Object { $_ -match '\d+ errors?' } | Select-Object -First 1
    if ($line -match '(\d+) errors?') { $err = [int]$Matches[1] }
    return @{ errors = $err; fixed = $null; syntax_errors = $null }
}

switch ($Tool) {
    "ruff"    { $parsed = Parse-Ruff $Combined }
    "pyright" { $parsed = Parse-Pyright $Combined }
    default   { $parsed = @{ errors = $null; fixed = $null; syntax_errors = $null } }
}

function Jv([object]$v) {
    if ($null -eq $v) { return "null" } else { return "$v" }
}

$line = "{`"kind`":`"run`",`"ts`":`"$Ts`",`"tool`":`"$Tool`",`"exit`":$ExitCode,`"errors`":$(Jv $parsed.errors),`"fixed`":$(Jv $parsed.fixed),`"syntax_errors`":$(Jv $parsed.syntax_errors)}"
Add-Content -Path $Jsonl -Value $line -Encoding UTF8

Remove-Item $OutFile, $ErrFile -Force -ErrorAction SilentlyContinue
exit $ExitCode
