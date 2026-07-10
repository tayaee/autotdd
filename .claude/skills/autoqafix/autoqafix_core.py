#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""autoqafix_core — safety-net primitives shared by every autoqafix entry
point (docs/autoqafix-design.md "루프", "뮤텍스"). Lives alongside the
scripts that import it (`.claude/skills/autoqafix/`), so callers in this
directory can `import autoqafix_core` with no sys.path surgery.

Run this file directly with --selftest to exercise every function below
without touching this repo's own git state (each self-test works inside
its own scratch temp directory).
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

LOCK_REL_PATH = ".git/autoqafix.lock"
DEFAULT_LOCK_STALE_SEC = 14400  # 4 hours


def _msg(reason: str, action: str) -> str:
    return f"[원인] {reason}\n[조치] {action}"


def preflight(role: str, repo: Path) -> list[str]:
    """Return a list of failure messages (empty = all checks passed).

    Each message is exactly two lines: "[원인] ...\\n[조치] ...". `repo`
    is the directory being preflighted -- every check below runs against
    it explicitly (rather than the process's os.getcwd()) so callers can
    preflight a fixture or a different checkout without chdir'ing.
    """
    repo = Path(repo)
    failures: list[str] = []

    # ① repo가 git 루트인지 (git rev-parse --show-toplevel == repo)
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(repo), capture_output=True, text=True, timeout=10,
        )
        top = Path(proc.stdout.strip()).resolve() if proc.returncode == 0 and proc.stdout.strip() else None
    except Exception:
        top = None
    if top is None or top != repo.resolve():
        failures.append(_msg("cwd가 git repo 루트가 아님", "repo 루트에서 실행하세요"))

    # ② issues/ 존재
    if not (repo / "issues").is_dir():
        failures.append(_msg("issues/ 없음", "issues/ 디렉토리를 생성하세요"))

    # ③ role==qa면 logs/ 존재
    if role == "qa" and not (repo / "logs").is_dir():
        failures.append(_msg("logs/ 없음", "logs/ 디렉토리를 생성하거나 로그 경로를 확인하세요"))

    # ④ uv가 PATH에 있는지
    if shutil.which("uv") is None:
        failures.append(_msg("uv가 PATH에 없음", "uv 설치 또는 PATH 추가"))

    # ⑤ git user.name / user.email 설정됨
    for key in ("user.name", "user.email"):
        try:
            proc = subprocess.run(
                ["git", "config", key],
                cwd=str(repo), capture_output=True, text=True, timeout=10,
            )
            ok = proc.returncode == 0 and bool(proc.stdout.strip())
        except Exception:
            ok = False
        if not ok:
            failures.append(_msg(f"git config {key} 미설정", f"git config {key} <값>으로 설정하세요"))

    # ⑥ git ls-remote origin, 30초 내 성공
    exit_code, _, _, timed_out = run_with_timeout(
        ["git", "-C", str(repo), "ls-remote", "origin"], 30
    )
    if timed_out or exit_code != 0:
        failures.append(_msg("git ls-remote origin 실패 또는 30초 초과", "네트워크/원격 설정을 확인하세요"))

    # ⑦ role이 fix/dev면 필수 스킬 존재
    if role in ("fix", "dev"):
        for skill in ("autotdd", "tdd2", "acpd"):
            if not (Path.home() / ".claude" / "skills" / skill).is_dir():
                failures.append(_msg(f"~/.claude/skills/{skill} 없음", "autotdd 설치 확인"))

    return failures


def _lock_path(repo: Path) -> Path:
    return Path(repo) / LOCK_REL_PATH


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # process exists, just owned by someone else
    except OSError:
        return False
    return True


def _read_lock(path: Path) -> dict[str, str] | None:
    try:
        content = path.read_text()
    except FileNotFoundError:
        return None
    data: dict[str, str] = {}
    for line in content.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            data[k.strip()] = v.strip()
    return data


def acquire_lock(role: str, repo: Path) -> bool:
    """Try to acquire <repo>/.git/autoqafix.lock. Reclaims a lock whose
    owning PID is dead (same host) or that's older than
    AUTOQAFIX_LOCK_STALE_SEC (default 4h). Otherwise returns False --
    caller should report "이미 <role>이 실행 중 (<host>, <start>)"."""
    path = _lock_path(repo)
    existing = _read_lock(path)
    if existing:
        stale_sec = int(os.environ.get("AUTOQAFIX_LOCK_STALE_SEC", str(DEFAULT_LOCK_STALE_SEC)))
        same_host = existing.get("host") == socket.gethostname()
        pid_dead = same_host and not _pid_alive(int(existing.get("pid") or "0"))

        age_sec = None
        try:
            start_dt = datetime.fromisoformat(existing.get("start", ""))
            if start_dt.tzinfo is None:
                start_dt = start_dt.replace(tzinfo=timezone.utc)
            age_sec = (datetime.now(timezone.utc) - start_dt).total_seconds()
        except Exception:
            pass
        is_stale = age_sec is not None and age_sec > stale_sec

        if not (pid_dead or is_stale):
            return False

    path.parent.mkdir(parents=True, exist_ok=True)
    content = (
        f"host={socket.gethostname()}\n"
        f"pid={os.getpid()}\n"
        f"role={role}\n"
        f"start={datetime.now(timezone.utc).isoformat()}\n"
    )
    path.write_text(content)
    return True


def release_lock(repo: Path) -> None:
    _lock_path(repo).unlink(missing_ok=True)


def clone_id(repo: Path) -> str:
    return hashlib.sha1(str(Path(repo).resolve()).encode()).hexdigest()[:12]


def state_dir(repo: Path) -> Path:
    d = Path.home() / ".cache" / "autoqafix" / clone_id(repo)
    d.mkdir(parents=True, exist_ok=True)
    return d


def run_with_timeout(cmd: list[str], timeout_sec: float) -> tuple[int, str, str, bool]:
    """Run cmd, killing the whole process group/tree if it exceeds
    timeout_sec, so grandchildren die too (a plain proc.kill() would
    leave them running). POSIX: start the child in its own session and
    SIGKILL the process group. Windows: subprocess.Popen with
    CREATE_NEW_PROCESS_GROUP + `taskkill /PID <pid> /T /F` is the
    equivalent -- not exercised in this repo's CI (Linux/WSL only)."""
    popen_kwargs: dict = {}
    if os.name == "posix":
        popen_kwargs["start_new_session"] = True
    elif os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **popen_kwargs
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout_sec)
        return proc.returncode, stdout, stderr, False
    except subprocess.TimeoutExpired:
        if os.name == "posix":
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"])
        stdout, stderr = proc.communicate()
        return -1, stdout, stderr, True


def _git(repo: Path, *args: str, timeout: float = 30) -> subprocess.CompletedProcess:
    """Run a git command scoped to `repo` only -- never touches global
    config (docs/autoqafix-design.md 번호 예약 프로토콜, requirement 2)."""
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=timeout
    )


def next_number(repo: Path, stream: str) -> int:
    """Highest existing <stream>-<N> across issues/ (archive included) and
    regression-tests/verify-<stream>-<N>.sh, plus 1. `stream` is "issue"
    or "autofix"."""
    repo = Path(repo)
    numbers: list[int] = []

    issue_pat = re.compile(rf"^{re.escape(stream)}-(\d+)")
    issues_dir = repo / "issues"
    if issues_dir.is_dir():
        for f in issues_dir.rglob(f"{stream}-*.md"):
            m = issue_pat.match(f.name)
            if m:
                numbers.append(int(m.group(1)))

    verify_pat = re.compile(rf"^verify-{re.escape(stream)}-(\d+)")
    verify_dir = repo / "regression-tests"
    if verify_dir.is_dir():
        for f in verify_dir.glob(f"verify-{stream}-*.sh"):
            m = verify_pat.match(f.name)
            if m:
                numbers.append(int(m.group(1)))

    return (max(numbers) + 1) if numbers else 1


def reserve_number(repo: Path, stream: str, summary: str, purpose: str) -> tuple[int, Path]:
    """Reserve the next <stream>-<N>, racing safely against other clones
    reserving concurrently: push success is the atomicity device. On a
    rejected push, undoes the local reservation commit, pulls, and
    retries with a freshly computed N (up to 10 attempts)."""
    repo = Path(repo)
    max_attempts = 10

    for _ in range(max_attempts):
        n = next_number(repo, stream)
        path = repo / "issues" / f"{stream}-{n}.md"
        reported_at = datetime.now(timezone.utc).isoformat()
        content = (
            f"# {stream}-{n}: {summary}\n"
            f"reported-by: {purpose}@{socket.gethostname()} {reported_at}\n"
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

        _git(repo, "add", str(path.relative_to(repo)))
        _git(repo, "commit", "-q", "-m", f"{stream}-{n}: 번호 예약")
        push = _git(repo, "push")
        if push.returncode == 0:
            return n, path

        # Push rejected (another clone won the race for N): drop our
        # reservation commit, sync up, and try again with a fresh N.
        _git(repo, "reset", "--hard", "HEAD~1")
        _git(repo, "pull", "--rebase", "-q")

    raise RuntimeError(f"reserve_number: gave up after {max_attempts} attempts for stream '{stream}'")


def finalize_item(repo: Path, path: Path, body: str) -> None:
    """Append `body` after a reserved item's two-line header and push the
    result. Reuses the reservation's own `<stream>-<N>: <summary>` line as
    the commit message. Retries once via pull --rebase on a rejected
    push."""
    repo = Path(repo)
    path = Path(path)

    existing = path.read_text()
    first_line = existing.splitlines()[0] if existing else ""
    _, _, summary = first_line.partition(": ")
    commit_prefix = path.stem  # e.g. "autofix-1"

    new_content = existing.rstrip("\n") + "\n" + body
    if not new_content.endswith("\n"):
        new_content += "\n"
    path.write_text(new_content)

    rel = path.relative_to(repo)
    _git(repo, "add", str(rel))
    _git(repo, "commit", "-q", "-m", f"{commit_prefix}: {summary}")
    push = _git(repo, "push")
    if push.returncode != 0:
        _git(repo, "pull", "--rebase", "-q")
        _git(repo, "push")


def _selftest() -> int:
    import tempfile

    ok = True

    def check(name: str, cond: bool) -> None:
        nonlocal ok
        print(f"[selftest] {name}: {'OK' if cond else 'FAIL'}", file=sys.stderr)
        if not cond:
            ok = False

    with tempfile.TemporaryDirectory() as td:
        p = Path(td)
        cid = clone_id(p)
        check("clone_id length is 12", len(cid) == 12)
        check("clone_id is deterministic", clone_id(p) == cid)

    with tempfile.TemporaryDirectory() as td:
        p = Path(td)
        sd = state_dir(p)
        check("state_dir is created", sd.is_dir())
        check("state_dir is keyed by clone_id", sd.name == clone_id(p))

    rc, out, _, timed_out = run_with_timeout(["echo", "hi"], 5)
    check("run_with_timeout completes a quick command", rc == 0 and not timed_out and "hi" in out)

    _, _, _, timed_out = run_with_timeout(["sleep", "10"], 1)
    check("run_with_timeout kills a slow command", timed_out)

    with tempfile.TemporaryDirectory() as td:
        p = Path(td)
        subprocess.run(["git", "init", "-q", str(p)], check=True)
        got1 = acquire_lock("qa", p)
        got2 = acquire_lock("fix", p)
        release_lock(p)
        got3 = acquire_lock("qa", p)
        release_lock(p)
        check("lock: acquire, deny, release, re-acquire", got1 and not got2 and got3)

    return 0 if ok else 1


def main() -> None:
    if "--selftest" in sys.argv[1:]:
        sys.exit(_selftest())
    print("autoqafix_core.py is a library module; run with --selftest to self-check.", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
