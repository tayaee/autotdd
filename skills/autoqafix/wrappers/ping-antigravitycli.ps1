# ping-antigravitycli.ps1 — diagnostic: confirms antigravitycli actually responds.
# Manual / post-install / incident-time use only — never part of the
# automated preflight loop (that would burn LLM credit every cycle).
# See CONTEXT.md "LLM 래퍼".
#
# NOTE: this script has not been executed in this environment (no
# PowerShell available under WSL) — verified by existence only, per
# issue-7's acceptance criteria. Treat as a careful manual port of the
# exercised ping-antigravitycli.sh until run for real on a Windows/PowerShell host.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WrapperName = "antigravitycli"
$Wrapper = if ($env:PING_WRAPPER) { $env:PING_WRAPPER } else { Join-Path $ScriptDir "$WrapperName.ps1" }
$Timeout = if ($env:PING_TIMEOUT) { [int]$env:PING_TIMEOUT } else { 120 }

if (-not (Test-Path $Wrapper -PathType Leaf)) {
    Write-Error "[원인] $WrapperName 없음"
    Write-Error "[조치] autotdd 설치 확인"
    exit 1
}

$start = Get-Date
$job = Start-Job -ScriptBlock { param($w) & $w -p "respond with exactly: pong" 2>&1 } -ArgumentList $Wrapper
$completed = Wait-Job $job -Timeout $Timeout
$elapsed = [int]((Get-Date) - $start).TotalSeconds

if (-not $completed) {
    Stop-Job $job | Out-Null
    Remove-Job $job -Force | Out-Null
    Write-Error "[원인] ${Timeout}초 내 무응답"
    Write-Error "[조치] 네트워크/서비스 상태, 쿼터 확인 (claude: claude.ai, qwen: 로컬 서비스 기동 여부)"
    exit 1
}

$output = Receive-Job $job
$jobFailed = $job.State -ne 'Completed'
Remove-Job $job -Force | Out-Null

if ((-not $jobFailed) -and (($output -join "`n") -match 'pong')) {
    Write-Output "OK $WrapperName (${elapsed}s)"
    exit 0
}

Write-Error "[원인] 응답 이상"
Write-Error "[조치] $WrapperName 단독 실행으로 에러 메시지 확인"
exit 1
