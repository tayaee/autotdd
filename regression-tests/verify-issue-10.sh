#!/usr/bin/env bash
# Verifies issue-10 acceptance criteria: autoqafix_core.py's preflight,
# lock, and run_with_timeout primitives.
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

pass() {
    echo "PASS: $1"
}

command -v uv > /dev/null 2>&1 || { echo "FAIL: uv not found on PATH" >&2; exit 1; }

if [ ! -f "$CORE" ]; then
    fail "missing $CORE"
    echo "aborting further checks: autoqafix_core.py not found"
    exit 1
fi

# --- criterion: --selftest exits 0 ---
if uv -q run "$CORE" --selftest > /dev/null 2>"$(mktemp)"; then
    pass "autoqafix_core.py --selftest exits 0"
else
    fail "autoqafix_core.py --selftest did not exit 0"
fi

# --- fixture repo setup (reuses issue-3's make-fixture-repo.sh) ---
fixture_path="$("$LIB/make-fixture-repo.sh" | tail -n 1)"
CLEANUP_DIRS+=("$fixture_path")
work="$fixture_path/work"

# --- everything below drives autoqafix_core.py's Python functions
# directly via a scratch test harness (PYTHONPATH-based import, no
# sys.path surgery needed inside autoqafix_core.py itself per its own
# design) so assertions can be precise instead of just CLI exit codes ---
harness="$(mktemp -d)/harness.py"
mkdir -p "$(dirname "$harness")"
CLEANUP_DIRS+=("$(dirname "$harness")")

cat > "$harness" << 'PYEOF'
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import autoqafix_core as core

work = Path(sys.argv[1])
results = []


def check(name, cond):
    results.append((name, bool(cond)))


# --- preflight("qa") passes on a fully-formed fixture repo ---
failures = core.preflight("qa", work)
check("preflight qa passes on fixture repo (empty list)", failures == [])

# --- removing logs/ makes preflight qa fail with a [원인] message ---
logs_dir = work / "logs"
logs_backup = work / "logs.bak"
logs_dir.rename(logs_backup)
try:
    failures2 = core.preflight("qa", work)
    check(
        "preflight qa fails with [원인] after logs/ removed",
        len(failures2) >= 1 and any("[원인]" in f for f in failures2),
    )
finally:
    logs_backup.rename(logs_dir)

# --- non-git directory triggers violation ① ---
import tempfile
with tempfile.TemporaryDirectory() as td:
    non_git = Path(td)
    failures3 = core.preflight("qa", non_git)
    check(
        "non-git directory triggers a git-root violation",
        any("git repo 루트" in f for f in failures3),
    )

# --- lock: acquire True -> acquire (other role) False -> release -> acquire True ---
with tempfile.TemporaryDirectory() as td:
    lock_repo = Path(td)
    subprocess.run(["git", "init", "-q", str(lock_repo)], check=True)
    got1 = core.acquire_lock("qa", lock_repo)
    got2 = core.acquire_lock("fix", lock_repo)
    core.release_lock(lock_repo)
    got3 = core.acquire_lock("qa", lock_repo)
    core.release_lock(lock_repo)
    check("lock: acquire True, second-role acquire False, release then True", got1 and not got2 and got3)

# --- lock: start manipulated to 5 hours ago is reclaimed ---
with tempfile.TemporaryDirectory() as td:
    stale_repo = Path(td)
    subprocess.run(["git", "init", "-q", str(stale_repo)], check=True)
    lock_path = stale_repo / core.LOCK_REL_PATH
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    stale_start = (datetime.now(timezone.utc) - timedelta(hours=5)).isoformat()
    import socket as _socket
    lock_path.write_text(
        f"host={_socket.gethostname()}\npid={os.getpid()}\nrole=qa\nstart={stale_start}\n"
    )
    reclaimed = core.acquire_lock("fix", stale_repo)
    core.release_lock(stale_repo)
    check("5-hour-old lock is reclaimed as stale", reclaimed)

# --- run_with_timeout(["sleep", "10"], 1) times out around 1s ---
t0 = time.time()
rc, out, err, timed_out = core.run_with_timeout(["sleep", "10"], 1)
elapsed = time.time() - t0
check("run_with_timeout sleep-10/timeout-1 -> timed_out True", timed_out)
check("run_with_timeout sleep-10/timeout-1 -> elapsed within [0.5, 8]s", 0.5 <= elapsed <= 8)

all_ok = all(ok for _, ok in results)
for name, ok in results:
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all_ok else 1)
PYEOF

PYTHONPATH="$SKILL_DIR" python3 "$harness" "$work"
harness_rc=$?
[ "$harness_rc" -eq 0 ] || fail "python harness reported at least one failure (see PASS/FAIL lines above)"

if [ "$FAIL" -eq 0 ]; then
    echo "All issue-10 acceptance checks passed."
    exit 0
else
    echo "One or more issue-10 acceptance checks failed."
    exit 1
fi
