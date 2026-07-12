#!/bin/bash
# verify-issue-22.sh — generalize three SKILL.md files to recognize
# two issue streams (issue-N, autofix-N) and exclude suffix files
# (v2: __STATE-later/__STATE-manual/__STATE-agent-failed 태그 — issue-39에서 supersede).
#
# Per issue-22 acceptance criteria:
#   1. All 3 SKILL.md mention 'autofix-' string
#   2. All 3 SKILL.md mention state-tag exclusion (__STATE- etc)
#   3. tdd2 SKILL.md has verify-<stream> placeholder in path guidance
#
# Plus issue-body requirement: aacp.sh also generalized to recognize both
# streams (the auxiliary script that lives next to acpd SKILL.md).

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills"
SKILLS=(tdd2 autotdd acpd)

pass=0
fail=0
declare -a failures

assert_in_skill() {
    local skill="$1" pat="$2" desc="$3"
    local file="$SKILL_DIR/$skill/SKILL.md"
    if grep -qE -e "$pat" "$file" 2>/dev/null; then
        echo "[PASS] $skill/SKILL.md contains: $desc"
        pass=$((pass+1))
    else
        echo "[FAIL] $skill/SKILL.md missing: $desc (pattern: $pat)"
        fail=$((fail+1))
        failures+=("$skill: $desc")
    fi
}

# Acceptance #1: all 3 SKILL.md mention 'autofix-'
for s in "${SKILLS[@]}"; do
    assert_in_skill "$s" 'autofix-' 'autofix- stream reference'
done

# Acceptance #2: all 3 SKILL.md mention suffix exclusion
for s in "${SKILLS[@]}"; do
    assert_in_skill "$s" '__STATE-' 'state-tag exclusion (__STATE-later/-manual/-agent-failed)'
done

# Acceptance #3: tdd2 SKILL.md has verify-<stream> placeholder
assert_in_skill "tdd2" 'verify-<' 'verify-<stream> placeholder in path guidance'

# Body requirement: aacp.sh recognizes both streams
AACP="$SKILL_DIR/acpd/aacp.sh"
if grep -qE -e 'autofix-' "$AACP" 2>/dev/null; then
    echo "[PASS] aacp.sh: autofix- stream recognized"
    pass=$((pass+1))
else
    echo "[FAIL] aacp.sh: autofix- stream not recognized"
    fail=$((fail+1))
    failures+=("aacp.sh: autofix-")
fi

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