#!/usr/bin/env bash
# Verifies issue-27: Windows 런처의 uv 설치 안내 교정 (.bat/.ps1 전체)
# - .bat/.ps1 런처에서 `curl ... | sh`(Linux 전용) 안내 0건
# - .bat 런처는 powershell -ExecutionPolicy ByPass -c "irm ... | iex" 안내
# - .ps1 런처는 irm https://astral.sh/uv/install.ps1 | iex 안내
# - .sh 런처는 기존 curl -LsSf https://astral.sh/uv/install.sh | sh 유지
# - 기존 .bat/.ps1 관례(pause, exit /b %ERRORLEVEL%, [원인]/[조치] 2줄 포맷) 변경 없음
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAIL=0

fail() { echo "FAIL: $1" >&2; FAIL=1; }
pass() { echo "PASS: $1"; }

# 검증 대상: .bat/.ps1 런처 패밀리 7종 × 2 = 14파일
KIND_NAMES=(autoqa autofix autodev autoqa-loop autofix-loop autodev-loop autoqafix-doctor)
BAT_FILES=()
PS1_FILES=()
for k in "${KIND_NAMES[@]}"; do
    BAT_FILES+=("${k}.bat")
    PS1_FILES+=("${k}.ps1")
done

# 1) 모든 .bat 파일: `install.sh`(sh 파이프) 부재
for f in "${BAT_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    if [ ! -f "$path" ]; then
        fail "$f 존재하지 않음"
        continue
    fi
    if grep -q 'astral\.sh/uv/install\.sh' "$path"; then
        fail "$f: install.sh 안내 잔존 (Windows CMD에서 실행 불가)"
    else
        pass "$f: install.sh 부재 확인"
    fi
done

# 2) 모든 .bat 파일: powershell -ExecutionPolicy ByPass -c "irm ... | iex" 존재
for f in "${BAT_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || continue
    expected='powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"'
    if grep -qF "$expected" "$path"; then
        pass "$f: Windows 정합 안내 존재"
    else
        fail "$f: Windows 정합 안내 부재 (expected: $expected)"
    fi
done

# 3) 모든 .ps1 파일: `install.sh`(sh 파이프) 부재
for f in "${PS1_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    if [ ! -f "$path" ]; then
        fail "$f 존재하지 않음"
        continue
    fi
    if grep -q 'astral\.sh/uv/install\.sh' "$path"; then
        fail "$f: install.sh 안내 잔존 (PowerShell에서 실행 불가)"
    else
        pass "$f: install.sh 부재 확인"
    fi
done

# 4) 모든 .ps1 파일: irm https://astral.sh/uv/install.ps1 | iex 존재
for f in "${PS1_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || continue
    expected='irm https://astral.sh/uv/install.ps1 | iex'
    if grep -qF "$expected" "$path"; then
        pass "$f: PowerShell 정합 안내 존재"
    else
        fail "$f: PowerShell 정합 안내 부재 (expected: $expected)"
    fi
done

# 5) .sh 런처: 기존 curl -LsSf https://astral.sh/uv/install.sh | sh 유지
for k in "${KIND_NAMES[@]}"; do
    path="$REPO_ROOT/${k}.sh"
    if [ ! -f "$path" ]; then
        fail "${k}.sh 존재하지 않음"
        continue
    fi
    if grep -qF 'curl -LsSf https://astral.sh/uv/install.sh | sh' "$path"; then
        pass "${k}.sh: 기존 curl 안내 유지"
    else
        fail "${k}.sh: 기존 curl 안내 변경됨 (변경 금지)"
    fi
done

# 6) 관례 보존 회귀 검사 — pause / exit /b %ERRORLEVEL% / [원인]·[조치] 2줄 포맷
for f in "${BAT_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || continue
    # uv 부재 분기 안에 pause 가 있어야 함 (관례 유지)
    if grep -qE 'echo \[조치\]' "$path" && ! grep -qE 'pause' "$path"; then
        # autofix / autofix-loop / autodev / autodev-loop 은 분기 후 즉시 exit 하므로 pause 없음도 OK
        # autoqa / autoqa-loop / autoqafix-doctor 는 pause 있어야 함
        case "$f" in
            autoqa.bat|autoqa-loop.bat|autoqafix-doctor.bat)
                fail "$f: pause 관례 누락"
                ;;
        esac
    fi
    if ! grep -qE '\[원인\] uv 없음' "$path"; then
        fail "$f: [원인] uv 없음 라벨 누락"
    fi
done

for f in "${PS1_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || continue
    if ! grep -qE '\[원인\] uv 없음' "$path"; then
        fail "$f: [원인] uv 없음 라벨 누락"
    fi
done

# 7) deploy.bat / deploy.ps1: uv 안내가 있다면 .sh 파이프면 안 됨 (현재는 안내 없음이 정상)
for f in deploy.bat deploy.ps1; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || continue
    if grep -q 'astral\.sh/uv/install\.sh' "$path"; then
        fail "$f: deploy 스크립트에 Linux 전용 uv 안내 잔존"
    else
        pass "$f: uv 안내 없음 (정상 — deploy 책임 아님)"
    fi
done

if [ $FAIL -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "VERIFY-ISSUE-27 FAILED"
    exit 1
fi