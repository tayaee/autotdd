#!/bin/bash
# verify-issue-35.sh — contract tests for the autorevfix SKILL.md.
#
# Static verification that:
#   - SKILL.md exists with valid frontmatter (name, description)
#   - Required sections (6) and step markers (4) are present
#   - All 10 wrappers (5 outer + 5 inner) are referenced by name
#   - SKILL.md body contains NO secret literal (defense in depth)
#   - All 10 wrappers exist at the expected path and are executable
#
# Exit codes:
#   0 — all assertions pass
#   1 — at least one assertion failed
#   2 — environment not set up

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_PATH="$REPO_ROOT/.claude/skills/autorevfix/SKILL.md"
WRAPPERS_DIR="/home/user1/git/harness-project/.local/bin"

WRAPPERS_OUTER=(sonnet minimax qwen gemini fable)
WRAPPERS_INNER=(sonnet5 minimax3 qwen36 gemini35 fable5)

pass=0
fail=0
declare -a failures

assert_file_exists() {
    local p="$1" desc="$2"
    if [ -e "$p" ]; then
        echo "[PASS] exists: $desc"
        pass=$((pass+1))
    else
        echo "[FAIL] missing: $desc at $p"
        fail=$((fail+1))
        failures+=("$desc missing")
    fi
}

assert_grep() {
    local pat="$1" file="$2" desc="$3"
    if grep -qE -e "$pat" "$file" 2>/dev/null; then
        echo "[PASS] grep: $desc"
        pass=$((pass+1))
    else
        echo "[FAIL] grep miss: $desc (pattern: $pat)"
        fail=$((fail+1))
        failures+=("$desc missing")
    fi
}

echo "=== verify-issue-35.sh ==="
echo "Repo:      $REPO_ROOT"
echo "Skill:     $SKILL_PATH"
echo "Wrappers:  $WRAPPERS_DIR"
echo ""

# Pre-flight
if [ ! -d "$REPO_ROOT/.claude/skills" ]; then
    echo "[FATAL] no .claude/skills/ directory"
    exit 2
fi
if [ ! -d "$WRAPPERS_DIR" ]; then
    echo "[FATAL] harness-project wrappers dir missing at $WRAPPERS_DIR"
    exit 2
fi

# SKILL.md exists
assert_file_exists "$SKILL_PATH" "SKILL.md"
if [ ! -f "$SKILL_PATH" ]; then
    echo "[FATAL] SKILL.md missing — cannot continue"
    exit 2
fi

# Frontmatter
assert_grep '^name:\s+autorevfix\s*$' "$SKILL_PATH" "frontmatter name=autorevfix"
assert_grep '^description:' "$SKILL_PATH" "frontmatter description"

# Required sections
for section in \
    "## Argument parsing" \
    "## cwd validation" \
    "## Per-issue flow" \
    "## Failure policy" \
    "## Idempotency" \
    "## Forbidden"; do
    assert_grep "^${section}\$" "$SKILL_PATH" "section: $section"
done

# 4 step markers in flow
for step in \
    "Step 1 — Coder MVP" \
    "Step 2 — Reviewers" \
    "Step 3 — Planner" \
    "Step 4 — Coder re-fix"; do
    assert_grep "${step}" "$SKILL_PATH" "marker: $step"
done

# Flag references
for flag in --model --coder --reviewers --planner; do
    assert_grep "${flag}\b" "$SKILL_PATH" "flag: ${flag}"
done

# Wrapper references (5 outer + 5 inner = 10)
for w in "${WRAPPERS_OUTER[@]}" "${WRAPPERS_INNER[@]}"; do
    assert_grep "${w}-cli\.sh" "$SKILL_PATH" "wrapper ref: ${w}-cli.sh"
done

# Secrets literal guard (defense in depth)
# Catches: MINIMAX_API_KEY=<value>, sk-..., key-..., anthropic api keys.
if grep -qE 'MINIMAX_API_KEY=[A-Za-z0-9]|sk-[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|key-[A-Za-z0-9]{20,}' "$SKILL_PATH"; then
    echo "[FAIL] SKILL.md contains a secret literal — must be wrapper-only"
    fail=$((fail+1))
    failures+=("secret literal in SKILL.md")
else
    echo "[PASS] SKILL.md free of literal secrets"
    pass=$((pass+1))
fi

# Wrappers exist + executable (10 total)
for w in "${WRAPPERS_OUTER[@]}" "${WRAPPERS_INNER[@]}"; do
    p="$WRAPPERS_DIR/${w}-cli.sh"
    if [ -x "$p" ]; then
        echo "[PASS] wrapper exec: ${w}-cli.sh"
        pass=$((pass+1))
    else
        echo "[FAIL] wrapper missing or not exec: ${w}-cli.sh at $p"
        fail=$((fail+1))
        failures+=("wrapper ${w}-cli.sh")
    fi
done

# Done
echo ""
echo "=== Summary ==="
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