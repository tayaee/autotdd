#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import argparse
import sys
import subprocess
from pathlib import Path

# autoqafix_core.py와 같은 위치이므로 임포트 가능
import autoqafix_core as core

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=str, help="Repository root path")
    args = parser.parse_args()

    repo_path = Path(args.repo).resolve()

    # 1. preflight
    failures = core.preflight("qa", repo_path)
    if failures:
        for fail_msg in failures:
            print(fail_msg, file=sys.stderr)
        sys.exit(1)

    # 2. acquire_lock
    lock_acquired = core.acquire_lock("qa", repo_path)
    if not lock_acquired:
        lock_info = core.peek_lock(repo_path)
        if lock_info:
            host = lock_info.get("host", "unknown")
            start = lock_info.get("start", "unknown")
            print(f"이미 qa이 실행 중 ({host}, {start})", file=sys.stderr)
        else:
            print("이미 qa이 실행 중", file=sys.stderr)
        sys.exit(3)

    # 3. error-to-autofix 실행 및 락 해제
    try:
        script_path = Path(__file__).parent / "error-to-autofix.py"
        proc = subprocess.run([sys.executable, str(script_path), "--repo", str(repo_path)])
        sys.exit(proc.returncode)
    finally:
        core.release_lock(repo_path)

if __name__ == "__main__":
    main()
