#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""autofix — implementation engine for the autofix / autodev streams
(docs/autoqafix-design.md "autofix / autodev"). Engine skeleton from
issue-15: agent worktree at state_dir/worktree, per-item LLM re-selection,
`tier stamp` for items missing `agent-tier:`, tier matching, then dispatch
(here a stub — real archive dispatch lands in issue-16).

Stream is selected by --stream (default autofix; pass `issue` for autodev).
Role passed to preflight/lock follows: autofix → fix, autodev → dev.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import autoqafix_core as core

STREAM_DEFAULT = "autofix"
STREAMS = ("autofix", "issue")
SUFFIXES = ("-later", "-manual", "-agent-failed")
SCRIPT_DIR = Path(__file__).resolve().parent
WRAPPER_DEFAULT_DIR = SCRIPT_DIR / "wrappers"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--repo", required=True, help="Repository root path")
    p.add_argument(
        "--stream",
        choices=STREAMS,
        default=STREAM_DEFAULT,
        help=f"Stream to operate on (default: {STREAM_DEFAULT})",
    )
    return p.parse_args()


def stream_to_role(stream: str) -> str:
    """autofix → fix (issue-14 convention), autodev → dev."""
    return "fix" if stream == "autofix" else "dev"


def ensure_worktree(repo: Path, worktree: Path) -> None:
    """Create the agent worktree, or fast-forward an existing one.

    The first-time command is `git worktree add --detach <path> main`. The
    `--detach` is necessary: when the human's main checkout is already on
    branch `main`, git refuses to add a second worktree that also checks
    out `main` ("fatal: 'main' is already used by worktree ..."). Detached
    HEAD at main's tip still tracks the same commit, satisfies the design
    "main 추적" semantics, and lets the agent commit + push to origin/main
    without disturbing the human's working tree.

    Subsequent runs do `git -C <path> pull --rebase origin main` (explicit
    remote + branch because detached HEADs have no upstream tracking).
    """
    if worktree.exists():
        subprocess.run(
            ["git", "-C", str(worktree), "pull", "--rebase", "origin", "main"],
            check=True, capture_output=True, text=True, timeout=30,
        )
        return
    worktree.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "-C", str(repo), "worktree", "add", "--detach", str(worktree), "main"],
        check=True, capture_output=True, text=True,
    )


def parse_wrapper_spec(spec: str) -> dict[str, str]:
    """`name:tier,...` → {name: tier}."""
    out: dict[str, str] = {}
    for entry in spec.split(","):
        entry = entry.strip()
        if not entry:
            continue
        name, _, tier = entry.partition(":")
        name = name.strip()
        tier = tier.strip()
        if name and tier:
            out[name] = tier
    return out


def enumerate_items(worktree: Path, stream: str) -> list[Path]:
    """Return `issues/<stream>-<N>.md` paths inside `worktree`, sorted by N
    ascending. Excludes:
      * Files with a state suffix (-later / -manual / -agent-failed)
      * Reservation-in-progress files (no `## ` section yet)
    """
    issues_dir = worktree / "issues"
    if not issues_dir.is_dir():
        return []
    pattern = re.compile(
        rf"^{re.escape(stream)}-(\d+)(?:-({'|'.join(s.lstrip('-') for s in SUFFIXES)}))?\.md$"
    )
    found: list[tuple[int, Path]] = []
    for f in sorted(issues_dir.iterdir()):
        if not f.is_file():
            continue
        m = pattern.match(f.name)
        if not m:
            continue
        if m.group(2):  # has a recognized state suffix
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if "## " not in text:
            # Reservation in progress (only header lines exist).
            continue
        found.append((int(m.group(1)), f))
    found.sort(key=lambda t: t[0])
    return [p for _, p in found]


def select_llm() -> tuple[str | None, dict[str, str]]:
    """Run select-llm and parse AUTOQAFIX_WRAPPERS for tier lookups. Returns
    (selected_wrapper_name_or_None, {wrapper_name: tier})."""
    spec = os.environ.get(
        "AUTOQAFIX_WRAPPERS", "claudecli:paid,minimaxcli:paid,qwencli:local"
    )
    tiers = parse_wrapper_spec(spec)
    forced = os.environ.get("AUTOQAFIX_WRAPPER")
    if forced:
        return forced, tiers
    select_llm_path = SCRIPT_DIR / "select-llm.py"
    try:
        proc = subprocess.run(
            ["uv", "-q", "run", str(select_llm_path)],
            capture_output=True, text=True, timeout=60,
        )
    except Exception:
        return None, tiers
    if proc.returncode != 0:
        return None, tiers
    return proc.stdout.strip(), tiers


def read_agent_tier(path: Path) -> str | None:
    """Read the existing `agent-tier:` value if present, else None."""
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("agent-tier:"):
            return s.split(":", 1)[1].strip()
    return None


def judge_tier(item: Path, wrapper: str, wrapper_path: Path) -> str | None:
    """Run the wrapper with light timeout, parse trailing `TIER: <value>`
    line. Returns tier or None on parse / runner failure."""
    try:
        content = item.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return None
    light_timeout = float(os.environ.get("AUTOQAFIX_LIGHT_TIMEOUT", "1200"))
    rc, out, _, timed_out = core.run_with_timeout(
        ["bash", str(wrapper_path), "-p", content], light_timeout,
    )
    if timed_out or rc != 0:
        return None
    for line in reversed(out.splitlines()):
        m = re.match(r"^TIER:\s*(\S+)", line.strip())
        if m:
            tier = m.group(1).lower()
            if tier in ("local-ok", "paid-only", "manual"):
                return tier
    return None


def _git_or_die(worktree: Path, *args: str) -> None:
    """Wrapper around core._git that raises on non-zero exit so the engine
    never silently swallows push / commit failures (the worktree is a
    detached HEAD, so `git push` with no args fails by default — and
    issue-15's spec relies on every commit landing on origin/main)."""
    proc = core._git(worktree, *args)
    if proc.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed (rc={proc.returncode}): "
            f"{proc.stderr.strip() or proc.stdout.strip()}"
        )


def stamp_tier(worktree: Path, item: Path, tier: str) -> None:
    """Insert `agent-tier: <tier>` near the top (after reserved header lines),
    then commit and push inside the worktree."""
    try:
        original = item.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        original = ""
    lines = original.splitlines()

    stamp = f"agent-tier: {tier}"
    if any(ln.strip().startswith("agent-tier:") for ln in lines):
        new_lines = lines
    else:
        # Insert after the reserved header lines (lines that look like
        # `# foo: ...` or `reported-by: ...`) but before any body content.
        insert_idx = 0
        for i, ln in enumerate(lines):
            stripped = ln.lstrip()
            if (stripped.startswith("#") and ":" in stripped) or stripped.startswith("reported-by:"):
                insert_idx = i + 1
            else:
                break
        new_lines = lines[:insert_idx] + [stamp] + lines[insert_idx:]

    suffix = "" if original.endswith("\n") else "\n"
    item.write_text("\n".join(new_lines) + suffix)

    rel = item.relative_to(worktree)
    _git_or_die(worktree, "add", str(rel))
    _git_or_die(worktree, "commit", "-q", "-m", f"{item.stem}: agent-tier={tier}")
    # Detached HEAD needs explicit refspec to advance origin/main.
    _git_or_die(worktree, "push", "origin", "HEAD:main")


def rename_to_manual(worktree: Path, item: Path) -> None:
    """`git mv` to `<stem>-manual.md`, commit, push — inside the worktree."""
    new_path = item.parent / f"{item.stem}-manual.md"
    rel_old = item.relative_to(worktree)
    rel_new = new_path.relative_to(worktree)
    _git_or_die(worktree, "mv", str(rel_old), str(rel_new))
    _git_or_die(
        worktree, "commit", "-q", "-m", f"{new_path.stem}: 사람 담당으로 분류"
    )
    _git_or_die(worktree, "push", "origin", "HEAD:main")


def dispatch(item: Path, wrapper: str, stream: str, repo: Path) -> bool:
    """Run the wrapper inside the agent worktree and judge success by
    archive presence.

    Returns ``True`` when the item file has been archived by the wrapper,
    ``False`` on failure / timeout (the worktree is recovered and an
    ``-agent-failed`` record is written).
    """
    # Extract the item number from the filename (``autofix-<N>`` or
    # ``issue-<N>``).
    stem = item.stem  # e.g. "autofix-3"
    _, _, n = stem.partition("-")
    if not n:
        return False

    wt = item.parent.parent  # worktree path (issues/ → worktree parent)
    # Walk up until we find the worktree root (state_dir / "worktree").
    # The worktree is at state_dir/worktree; items are at
    # state_dir/worktree/issues/<stream>-<N>.md
    # In a worktree, .git is a FILE (gitdir pointer), not a directory.
    for ancestor in item.parents:
        git_path = ancestor / ".git"
        if git_path.is_file() or git_path.is_dir():
            wt = ancestor
            break

    cmd = [
        wrapper, "-p",
        f"/autotdd {stream}-{n} worktree",
    ]
    timeout_sec = float(
        os.environ.get("AUTOQAFIX_IMPL_TIMEOUT", "10800")
    )

    # Set FAKE_TARGET so fake-wrapper knows which item to archive.
    env = dict(os.environ)
    env["FAKE_TARGET"] = str(item)

    rc, stdout, stderr, timed_out = core.run_with_timeout(
        cmd, timeout_sec, cwd=wt, env=env,
    )

    # ── success path ──────────────────────────────────────────────
    if not timed_out and rc == 0:
        # Pull to pick up any archive moves the wrapper committed.
        pull = core._git(wt, "pull", "--rebase", "origin", "main")
        if pull.returncode != 0:
            return False

        archive_pattern = f"{stream}-{n}.md"
        issues_dir = wt / "issues"
        if not issues_dir.is_dir():
            return False

        # Check direct file first.
        if (issues_dir / archive_pattern).is_file():
            return False  # not archived yet

        # Check archive/**/*.md.
        for af in issues_dir.rglob("archive/**/*.md"):
            if af.name == archive_pattern:
                return True

        return False

    # ── failure / timeout path ────────────────────────────────────
    # Capture item content BEFORE resetting the worktree.
    try:
        original_body = item.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        original_body = ""

    # Append 실패 기록 — BEFORE any git operations that might
    # remove the item file or the worktree itself.
    now = datetime.now(timezone.utc).isoformat()
    if timed_out:
        detail = f"timeout ({timeout_sec}s)"
    else:
        detail = f"exit {rc}"

    # Last 3 lines of stderr.
    last_lines = "\n".join(
        stderr.strip().splitlines()[-3:]
    ) if stderr.strip() else "(no stderr)"

    record = f"- {now} {wrapper}: {detail}\n{last_lines}\n"

    # Ensure ## agent 실패 기록 section exists.
    body = original_body
    if "## agent 실패 기록" not in body:
        body += "\n## agent 실패 기록\n"

    body += record
    item.write_text(body)

    # git mv to -agent-failed, commit, push — inside the worktree.
    new_name = f"{stem}-agent-failed.md"
    new_path = item.parent / new_name
    rel_old = item.relative_to(wt)
    rel_new = new_path.relative_to(wt)
    _git_or_die(wt, "mv", str(rel_old), str(rel_new))
    _git_or_die(wt, "add", str(rel_new))  # Stage the content change
    _git_or_die(
        wt, "commit", "-q",
        "-m", f"{new_path.stem}: agent 실패 — {detail}",
    )
    _git_or_die(wt, "push", "origin", "HEAD:main")

    # Recover worktree — prune AFTER pushing the -agent-failed record.
    # git worktree prune must run from the main repo (the fixture),
    # not from the worktree itself.
    core._git(repo, "worktree", "prune")

    return False


def run(repo: Path, stream: str) -> int:
    """Top-level work after preflight + lock acquisition: prepare worktree,
    enumerate items, iterate per the design's ①/②/③/④ sequence."""
    sd = core.state_dir(repo)
    worktree = sd / "worktree"
    wrapper_dir = Path(
        os.environ.get("AUTOQAFIX_WRAPPER_DIR", str(WRAPPER_DEFAULT_DIR))
    )

    ensure_worktree(repo, worktree)
    items = enumerate_items(worktree, stream)

    processed = 0  # dispatched + renamed-to-manual
    skipped = 0    # not-this-time skip (already-correct tier or wrong tier)
    stamped = 0    # newly-stamped items
    fixed = 0      # items successfully archived by dispatch

    for item in items:
        selected, tiers = select_llm()
        if not selected:
            print("LLM 부적격, 대기")
            break

        tier_sel = tiers.get(selected, "local")
        item_tier = read_agent_tier(item)

        # ② Tier stamping for un-stamped items (paid selection only).
        if item_tier is None:
            if tier_sel != "paid":
                # Only local is reachable, and local can't run tier judgement.
                skipped += 1
                continue
            wp = wrapper_dir / f"{selected}.sh"
            if not wp.is_file():
                skipped += 1
                continue
            judged = judge_tier(item, selected, wp)
            if judged is None:
                skipped += 1
                continue
            stamp_tier(worktree, item, judged)
            item_tier = judged
            stamped += 1

        # ③ Tier matching.
        if tier_sel == "local" and item_tier == "paid-only":
            skipped += 1
            continue
        if item_tier == "manual":
            rename_to_manual(worktree, item)
            processed += 1
            continue

        # ④ Match passed → dispatch (real archive dispatch).
        if dispatch(item, selected, stream, repo):
            fixed += 1
        processed += 1

    print(
        f"처리: {processed}건, 건너뜀: {skipped}건, 스탬프 추가: {stamped}건"
    )
    print(f"FIXED={fixed}")
    return 0


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()
    stream = args.stream
    role = stream_to_role(stream)

    failures = core.preflight(role, repo)
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        return 1

    if not core.acquire_lock(role, repo):
        lock_path = core._lock_path(repo)
        info = core._read_lock(lock_path) or {}
        host = info.get("host", "unknown")
        start = info.get("start", "unknown")
        print(f"이미 {role}이 실행 중 ({host}, {start})", file=sys.stderr)
        return 3

    try:
        return run(repo, stream)
    finally:
        core.release_lock(repo)


if __name__ == "__main__":
    sys.exit(main())
