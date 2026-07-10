#!/usr/bin/env bash
# Creates a throwaway fixture git repo (bare origin.git + a clone at work/)
# under a fresh temp directory, seeds it with logs/ and src/ fixtures, and
# prints the temp directory's path as the last line of stdout.
#
# Used by regression tests that need a real, independent git repo without
# touching this project's own repo or spending real LLM credit.
set -euo pipefail

FIXTURE_DATE="2026-07-10"

tmp_dir="$(mktemp -d)"
origin_dir="$tmp_dir/origin.git"
work_dir="$tmp_dir/work"

git init --bare -q "$origin_dir"

git clone -q "$origin_dir" "$work_dir" 2>/dev/null
git -C "$work_dir" config user.name "Fixture Bot"
git -C "$work_dir" config user.email "fixture-bot@example.com"

mkdir -p "$work_dir/issues" "$work_dir/logs" "$work_dir/src"
touch "$work_dir/issues/.gitkeep"

log_file="$work_dir/logs/app.main.log"
: > "$log_file"

# ① same traceback block, repeated 5 times (identical content)
for i in 1 2 3 4 5; do
    {
        printf '%s 12:00:%02d,000 [ERROR] app.main - Unhandled exception\n' "$FIXTURE_DATE" "$i"
        printf 'Traceback (most recent call last):\n'
        printf '  File "work/src/app.py", line 42, in process\n'
        printf '    result = compute(x)\n'
        printf 'ValueError: bad value\n'
    } >> "$log_file"
done

# ② three standalone [ERROR] lines, same message, differing only by number
for i in 1 2 3; do
    printf '%s 12:01:%02d,000 [ERROR] app.worker - Failed to process item %d\n' \
        "$FIXTURE_DATE" "$i" "$i" >> "$log_file"
done

# ③ two [WARNING] lines
for i in 1 2; do
    printf '%s 12:02:%02d,000 [WARNING] app.main - Retrying connection\n' \
        "$FIXTURE_DATE" "$i" >> "$log_file"
done

# ④ a bunch of [INFO] lines, also padding total line count to 30+
for i in $(seq 1 15); do
    printf '%s 12:03:%02d,000 [INFO] app.main - Heartbeat %d\n' \
        "$FIXTURE_DATE" "$i" "$i" >> "$log_file"
done

app_py="$work_dir/src/app.py"
{
    echo "#!/usr/bin/env python3"                                  # 1
    echo "\"\"\"Dummy fixture app used by regression tests only.\"\"\"" # 2
    echo ""                                                        # 3
    echo "import sys"                                              # 4
    echo ""                                                        # 5
    echo ""                                                        # 6
    echo "def compute(x):"                                         # 7
    echo "    return 1 / x"                                        # 8
    echo ""                                                        # 9
    echo ""                                                        # 10
    echo "def process(x):"                                         # 11
    for i in $(seq 1 30); do
        echo "    # filler line $i to pad this file for fixture purposes" # 12-41
    done
    echo "    result = compute(x)  # line 42: frame target for the fixture traceback" # 42
    echo "    return result"                                       # 43
    echo ""                                                        # 44
    echo ""                                                        # 45
    echo "if __name__ == '__main__':"                              # 46
    echo "    sys.exit(process(0))"                                # 47
    echo "# trailing filler 1"                                     # 48
    echo "# trailing filler 2"                                     # 49
    echo "# trailing filler 3"                                     # 50
} > "$app_py"

git -C "$work_dir" add -A
git -C "$work_dir" commit -q -m "Initial fixture commit"
git -C "$work_dir" branch -M main
git -C "$work_dir" push -q -u origin main

echo "$tmp_dir"
