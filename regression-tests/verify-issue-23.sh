#!/bin/bash
# verify-issue-23.sh — docs/SETUP-autoqafix.md has 7 required sections
# and every <autosdlc>/... path it references actually exists on disk.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/docs/SETUP-autoqafix.md"

pass=0
fail=0
declare -a failures

assert_grep() {
    local pat="$1" desc="$2"
    if grep -qE -e "$pat" "$DOC" 2>/dev/null; then
        echo "[PASS] $desc"
        pass=$((pass+1))
    else
        echo "[FAIL] $desc (pattern: $pat)"
        fail=$((fail+1))
        failures+=("$desc")
    fi
}

# Pre-flight: doc must exist
if [ ! -f "$DOC" ]; then
    echo "[FATAL] doc not found: $DOC"
    exit 2
fi

# 7 section titles per issue-23 requirement #1
assert_grep "^## 1\. 사전 준비"        "section 1 — 사전 준비"
assert_grep "^## 2\. 점검 순서"        "section 2 — 점검 순서"
assert_grep "^## 3\. Windows production 배치" "section 3 — Windows production 배치"
assert_grep "^## 4\. WSL 수동 사용"    "section 4 — WSL 수동 사용"
assert_grep "^## 5\. Claude Code 스킬" "section 5 — Claude Code 스킬"
assert_grep "^## 6\. 운영 규약 요약"    "section 6 — 운영 규약 요약"
assert_grep "^## 7\. 알려진 정리 작업"  "section 7 — 알려진 정리 작업"

# "시작 위치" mention (acceptance #3)
assert_grep "시작 위치" "시작 위치 setting mentioned"

# Path existence: extract every `<autosdlc>/<path>` literal from the doc
# and check that <REPO_ROOT>/<path> exists on disk.
echo ""
echo "=== <autosdlc>/... path existence ==="

paths=$(grep -oE '<autosdlc>/[^[:space:])`]+' "$DOC" | sed 's/<autosdlc>//' | sort -u)
if [ -z "$paths" ]; then
    echo "[INFO] no <autosdlc>/... paths found in doc"
fi
while IFS= read -r p; do
    [ -z "$p" ] && continue
    real="$REPO_ROOT$p"
    if [ -e "$real" ]; then
        echo "[PASS] path exists: <autosdlc>$p"
        pass=$((pass+1))
    else
        echo "[FAIL] path missing: <autosdlc>$p (expected at $real)"
        fail=$((fail+1))
        failures+=("path <autosdlc>$p")
    fi
done <<< "$paths"

echo ""
echo "Pass: $pass"
echo "Fail: $fail"
if [ $fail -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${failures[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
exit 0