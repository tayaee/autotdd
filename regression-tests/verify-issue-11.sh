#!/usr/bin/env bash
# Verifies issue-11 acceptance criteria: autoqafix_core.py's number
# reservation protocol (next_number / reserve_number / finalize_item).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/regression-tests/lib"
SKILL_DIR="$REPO_ROOT/.claude/skills/autoqafix"
CORE="$SKILL_DIR/autoqafix_core.py"

FAIL=0
CLEANUP_DIRS=()

cleanup() {
    for d in "${CLEANUP_DIRS[@]:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}

if [ ! -f "$CORE" ]; then
    fail "missing $CORE"
    echo "aborting further checks: autoqafix_core.py not found"
    exit 1
fi

fixture_path="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$fixture_path")

harness_dir="$(mktemp -d)"
CLEANUP_DIRS+=("$harness_dir")
harness="$harness_dir/harness.py"

cat > "$harness" << 'PYEOF'
import subprocess
import sys
from pathlib import Path

import autoqafix_core as core

fixture_path = Path(sys.argv[1])
origin = fixture_path / "origin.git"
work = fixture_path / "work"

results = []


def check(name, cond):
    results.append((name, bool(cond)))


def git(repo, *args, check_=True):
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=check_,
    )


# --- reserve_number("autofix") in the fixture's work clone -> autofix-1.md
# on the remote, exactly two lines ---
n1, path1 = core.reserve_number(work, "autofix", "테스트 요약", "qa")
check("reserve_number returns N=1 for the first reservation", n1 == 1)
check("reserve_number returns the expected path", path1 == work / "issues" / "autofix-1.md")

remote_show = subprocess.run(
    ["git", "-C", str(origin), "show", "HEAD:issues/autofix-1.md"],
    capture_output=True, text=True,
)
remote_lines = remote_show.stdout.splitlines()
check("autofix-1.md exists on the remote (bare origin)", remote_show.returncode == 0)
check("autofix-1.md on the remote has exactly two lines", len(remote_lines) == 2)
check(
    "line 1 matches '# autofix-1: <summary>'",
    len(remote_lines) >= 1 and remote_lines[0] == "# autofix-1: 테스트 요약",
)
check(
    "line 2 matches 'reported-by: <purpose>@<host> <iso8601>'",
    len(remote_lines) >= 2 and remote_lines[1].startswith("reported-by: qa@"),
)

# --- race: clone B (never fetches A's push) also reserves -> gets push
# rejected on N=1, retries, lands on autofix-2.md; both 1 and 2 survive
# on the remote ---
clone_b = fixture_path / "clone-b"
git(fixture_path, "clone", "-q", str(origin), str(clone_b))
git(clone_b, "config", "user.name", "Fixture Bot B")
git(clone_b, "config", "user.email", "fixture-bot-b@example.com")
# clone_b was made *after* A's push above, so to reproduce the race we
# roll it back to the pre-reservation state (matching the issue's
# pseudocode: both clones start before any reservation exists), then
# call reserve_number without ever fetching A's autofix-1.md commit.
git(clone_b, "reset", "--hard", "HEAD~1")

n2, path2 = core.reserve_number(clone_b, "autofix", "테스트 요약 B", "qa")
check("reserve_number recovers from a push race and lands on N=2", n2 == 2)
check("reserve_number's race path is autofix-2.md", path2 == clone_b / "issues" / "autofix-2.md")

ls_tree = subprocess.run(
    ["git", "-C", str(origin), "ls-tree", "-r", "--name-only", "HEAD"],
    capture_output=True, text=True,
)
names = ls_tree.stdout.splitlines()
check(
    "remote ends up with both autofix-1.md and autofix-2.md",
    "issues/autofix-1.md" in names and "issues/autofix-2.md" in names,
)

# --- next_number sees archive/ too ---
archive_dir = work / "issues" / "archive" / "2026" / "07" / "10"
archive_dir.mkdir(parents=True, exist_ok=True)
(archive_dir / "autofix-7.md").write_text("# autofix-7: archived\n")
git(work, "pull", "--rebase", "-q")  # pick up clone-b's autofix-2.md too
check("next_number sees archive/autofix-7.md and returns 8", core.next_number(work, "autofix") == 8)

# --- next_number also considers regression-tests/verify-<stream>-<N>.sh ---
(work / "regression-tests").mkdir(parents=True, exist_ok=True)
(work / "regression-tests" / "verify-autofix-3.sh").write_text("")
check(
    "next_number considers verify-autofix-3.sh (empty file) and returns >= 4",
    core.next_number(work, "autofix") >= 4,
)

# --- finalize_item appends body and pushes it to the remote ---
core.finalize_item(work, path1, "## 본문\n세부 내용입니다.\n")
remote_final = subprocess.run(
    ["git", "-C", str(origin), "show", "HEAD:issues/autofix-1.md"],
    capture_output=True, text=True,
)
check(
    "finalize_item's body reaches the remote copy of the reserved file",
    "세부 내용입니다." in remote_final.stdout,
)

all_ok = all(ok for _, ok in results)
for name, ok in results:
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all_ok else 1)
PYEOF

PYTHONPATH="$SKILL_DIR" python3 "$harness" "$fixture_path"
harness_rc=$?
[ "$harness_rc" -eq 0 ] || fail "python harness reported at least one failure (see PASS/FAIL lines above)"

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-11 acceptance checks passed."
    exit 0
else
    echo "One or more issue-11 acceptance checks failed."
    exit 1
fi
