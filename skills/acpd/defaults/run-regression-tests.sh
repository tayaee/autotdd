#!/usr/bin/env bash
# acpd default — used only when the target project has no
# ./run-regression-tests.sh of its own. Assumes CWD is already the target
# repo root. Runs every regression-tests/verify-issue-*.sh in order.
set -uo pipefail

PASS=0
FAIL=0
FAILED_SCRIPTS=()

shopt -s nullglob
for script in regression-tests/verify-issue-*.sh; do
    echo ""
    if bash "$script"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_SCRIPTS+=("$script")
    fi
done

echo ""
echo "============================="
echo "Regression results: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed scripts:"
    for s in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $s"
    done
    exit 1
fi
exit 0
