#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""select-llm — single implementation of the effective-remaining-usage LLM
selection rule (CONTEXT.md "유효 잔여율"; docs/autoqafix-design.md "LLM
선정"). Every autoqafix entry point that needs to pick an LLM wrapper
calls this script, so the rule lives in exactly one place.

stdout: the selected wrapper name (one line), or "none" if nothing usable
was found. Exit 0 normally; exit 2 only for the "none" case. Pass
--explain to also print every candidate's numbers and the decision
rationale to stderr (stdout still only ever carries the single selected
name / "none").
"""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

# select-llm.py lives at <repo_root>/.claude/skills/autoqafix/select-llm.py
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_WRAPPERS = "claudecli:paid,minimaxcli:paid,qwencli:local"


def parse_candidates(spec: str) -> list[tuple[str, str]]:
    """Parse "<name>:paid|local,..." preserving list order (= priority)."""
    candidates = []
    for entry in spec.split(","):
        entry = entry.strip()
        if not entry:
            continue
        name, _, tier = entry.partition(":")
        name = name.strip()
        tier = tier.strip()
        if name and tier:
            candidates.append((name, tier))
    return candidates


def usage_command(name: str) -> list[str] | None:
    env_key = f"AUTOQAFIX_USAGE_CMD_{name.upper()}"
    override = os.environ.get(env_key)
    if override is not None:
        return shlex.split(override)

    script = REPO_ROOT / ".claude" / "skills" / "autoqafix" / f"usage-{name}.py"
    if not script.exists():
        return None
    return ["uv", "-q", "run", str(script)]


def fetch_usage(name: str) -> dict | None:
    env_data = os.environ.get(f"AUTOQAFIX_USAGE_DATA_{name.upper()}")
    if env_data:
        try:
            return json.loads(env_data)
        except Exception as e:
            print(f"[경고] {name}: 주입된 usage 데이터 파싱 실패 ({e}) — 쿼리 시도", file=sys.stderr)

    cmd = usage_command(name)
    if cmd is None:
        print(f"[경고] {name}: usage 스크립트 없음 — 후보 제외", file=sys.stderr)
        return None
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except Exception as e:
        print(f"[경고] {name}: usage 명령 실행 실패 ({e}) — 후보 제외", file=sys.stderr)
        return None
    if proc.returncode != 0:
        print(f"[경고] {name}: usage 명령 exit={proc.returncode} — 후보 제외", file=sys.stderr)
        return None
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    if not lines:
        print(f"[경고] {name}: usage 출력 없음 — 후보 제외", file=sys.stderr)
        return None
    try:
        return json.loads(lines[-1])
    except Exception as e:
        print(f"[경고] {name}: usage 출력 파싱 실패 ({e}) — 후보 제외", file=sys.stderr)
        return None


def evaluate(candidates: list[tuple[str, str]], usage: dict[str, dict]) -> list[dict]:
    rows = []
    for name, tier in candidates:
        data = usage.get(name)
        if data is None:
            rows.append({
                "name": name, "tier": tier, "available": False,
                "five_hour": None, "weekly": None, "effective": None,
                "eligible": False,
            })
            continue
        available = bool(data.get("available", False))
        effective = data.get("effective_remaining_pct")
        eligible = tier == "paid" and available and effective is not None and effective >= 50
        rows.append({
            "name": name, "tier": tier, "available": available,
            "five_hour": data.get("five_hour_remaining_pct"),
            "weekly": data.get("weekly_remaining_pct"),
            "effective": effective, "eligible": eligible,
        })
    return rows


def select(rows: list[dict]) -> str | None:
    # Eligible paid candidates: largest effective wins; ties keep the
    # earlier list position, which is exactly what max() does when it
    # only replaces the running best on a strictly-greater value.
    paid_eligible = [r for r in rows if r["tier"] == "paid" and r["eligible"]]
    if paid_eligible:
        return max(paid_eligible, key=lambda r: r["effective"])["name"]

    for r in rows:
        if r["tier"] == "local" and r["available"]:
            return r["name"]

    return None


def print_explain(rows: list[dict], selected: str | None) -> None:
    header = f"{'wrapper':<16} {'tier':<6} {'available':<10} {'5h%':>5} {'wk%':>5} {'eff%':>5} {'eligible':<9} selected"
    print(header, file=sys.stderr)
    for r in rows:
        def fmt(v):
            return "-" if v is None else str(v)
        is_selected = "*" if r["name"] == selected else ""
        print(
            f"{r['name']:<16} {r['tier']:<6} {str(r['available']):<10} "
            f"{fmt(r['five_hour']):>5} {fmt(r['weekly']):>5} {fmt(r['effective']):>5} "
            f"{str(r['eligible']):<9} {is_selected}",
            file=sys.stderr,
        )
    print(f"decision: {selected if selected else 'none'}", file=sys.stderr)


def main() -> None:
    forced = os.environ.get("AUTOQAFIX_WRAPPER")
    if forced:
        print(forced)
        return

    explain = "--explain" in sys.argv[1:]

    spec = os.environ.get("AUTOQAFIX_WRAPPERS") or DEFAULT_WRAPPERS
    candidates = parse_candidates(spec)

    usage = {}
    for name, _ in candidates:
        data = fetch_usage(name)
        if data is not None:
            usage[name] = data

    rows = evaluate(candidates, usage)
    selected = select(rows)

    if explain:
        print_explain(rows, selected)

    if selected is None:
        print("none")
        sys.exit(2)

    print(selected)


if __name__ == "__main__":
    main()
