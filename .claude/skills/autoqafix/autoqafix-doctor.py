#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""autoqafix-doctor — 사전 점검 도구 (issue-20).

"이 repo에서 autoqafix 스위트가 동작할 것인가"를 실행 전에 진단한다.
preflight(issue-10)의 상위 집합: preflight 전 항목에 더해 래퍼 존재,
usage 스크립트 기동, select-llm 동작, deploy 스크립트 유무(WARN),
뮤텍스 상태, 필수 스킬 설치까지 본다.

각 항목은 `OK <항목>` 또는 `FAIL <항목>`(+`[원인]`/`[조치]`)을 출력.
deploy 스크립트 부재만은 FAIL이 아닌 WARN이다 — 그 파일은 대상 repo가
준비하는 것이며 이 도구는 절대 생성하지 않는다. exit code = FAIL 수
(WARN 미포함). `--ping`을 주면 후보 래퍼의 ping-<래퍼명>도 실행한다
(실 크레딧 소모 가능 — 기본은 실행하지 않음).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import sys
from pathlib import Path

import autofix
import autoqafix_core as core

SCRIPT_DIR = Path(__file__).resolve().parent
WRAPPER_DEFAULT_DIR = SCRIPT_DIR / "wrappers"
WRAPPERS_DEFAULT = "claudecli:paid,minimaxcli:paid,qwencli:local"
REQUIRED_SKILLS = ("autotdd", "tdd2", "acpd", "tdd")


class Doctor:
    def __init__(self) -> None:
        self.fails = 0

    def ok(self, item: str) -> None:
        print(f"OK {item}")

    def fail(self, item: str, reason: str, action: str) -> None:
        self.fails += 1
        print(f"FAIL {item}")
        print(f"[원인] {reason}")
        print(f"[조치] {action}")

    def fail_preformatted(self, item: str, msg: str) -> None:
        """preflight()가 이미 만든 [원인]/[조치] 2줄 메시지를 그대로 사용."""
        self.fails += 1
        print(f"FAIL {item}")
        print(msg)

    def warn(self, msg: str) -> None:
        print(f"WARN — {msg}")


def check_preflight(d: Doctor, repo: Path) -> None:
    """① preflight("qa")·preflight("fix") 전 항목."""
    for role in ("qa", "fix"):
        failures = core.preflight(role, repo)
        if failures:
            for msg in failures:
                d.fail_preformatted(f"preflight({role})", msg)
        else:
            d.ok(f"preflight({role})")


def check_wrappers(d: Doctor, names: list[str], wrapper_dir: Path) -> None:
    """② AUTOQAFIX_WRAPPERS의 래퍼들이 wrappers/ 또는 PATH에 존재."""
    for name in names:
        in_dir = any(
            (wrapper_dir / f"{name}{ext}").is_file() for ext in (".sh", ".ps1", ".bat")
        )
        if in_dir or shutil.which(name):
            d.ok(f"래퍼 {name}")
        else:
            d.fail(
                f"래퍼 {name}",
                f"{name}이 {wrapper_dir} 또는 PATH에 없음",
                "autotdd 설치 확인 또는 AUTOQAFIX_WRAPPERS에서 제거",
            )


def check_usage_scripts(d: Doctor, names: list[str]) -> None:
    """③ usage-<래퍼명>.py가 uv -q run으로 기동되고 유효 JSON을 내는가."""
    for name in names:
        item = f"usage-{name}.py"
        script = SCRIPT_DIR / item
        if not script.is_file():
            d.fail(item, f"{script} 없음", "autotdd 설치 확인")
            continue
        rc, out, _, timed_out = core.run_with_timeout(
            ["uv", "-q", "run", str(script)], 60,
        )
        if timed_out or rc != 0:
            detail = "60초 초과" if timed_out else f"exit {rc}"
            d.fail(item, f"기동 실패 ({detail})", f"uv -q run {script} 단독 실행으로 확인")
            continue
        try:
            json.loads(out)
        except ValueError:
            d.fail(item, "stdout이 유효 JSON이 아님", f"uv -q run {script} 출력 확인")
            continue
        d.ok(item)


def check_select_llm(d: Doctor, names: list[str]) -> None:
    """④ select-llm이 후보 래퍼명 또는 none을 내는가."""
    script = SCRIPT_DIR / "select-llm.py"
    _, out, _, timed_out = core.run_with_timeout(
        ["uv", "-q", "run", str(script)], 120,
    )
    selected = out.strip()
    # exit 2 = "none" 정상 경로 (issue-9) — 출력으로만 판정한다.
    if not timed_out and (selected in names or selected == "none"):
        d.ok(f"select-llm ({selected})")
    else:
        detail = "120초 초과" if timed_out else f"출력 '{selected}'"
        d.fail(
            "select-llm",
            f"후보 래퍼명도 none도 아님 ({detail})",
            f"uv -q run {script} --explain으로 확인",
        )


def check_deploy(d: Doctor, repo: Path) -> None:
    """⑤ deploy 스크립트 존재 — 부재는 FAIL이 아닌 WARN (대상 repo 소관,
    이 도구는 절대 생성하지 않는다)."""
    exts = (".sh", ".ps1", ".bat")
    found = any((repo / f"deploy{e}").is_file() for e in exts) or any(
        p.is_file() for e in exts for p in repo.glob(f"deploy-to-*{e}")
    )
    if found:
        d.ok("deploy 스크립트")
    else:
        d.warn("deploy 스크립트 없음, 파일이 없으므로 배포는 생략됩니다")


def check_lock(d: Doctor, repo: Path) -> None:
    """⑥ 뮤텍스 잠금이 현재 잡혀 있지 않은가."""
    info = core._read_lock(core._lock_path(repo))
    if info is None:
        d.ok("뮤텍스 잠금 없음")
        return
    same_host = info.get("host") == socket.gethostname()
    pid_dead = same_host and not core._pid_alive(int(info.get("pid") or "0"))
    if pid_dead:
        d.ok("뮤텍스 잠금 없음 (stale lock — 소유 프로세스 사망, 재획득 가능)")
    else:
        d.fail(
            "뮤텍스 잠금",
            f"이미 {info.get('role', '?')}이 실행 중 ({info.get('host', '?')}, {info.get('start', '?')})",
            "실행 종료를 기다리거나, 확실히 죽었으면 .git/autoqafix.lock 삭제",
        )


def check_skills(d: Doctor) -> None:
    """⑦ ~/.claude/skills/{autotdd,tdd2,acpd,tdd} 존재."""
    for skill in REQUIRED_SKILLS:
        if (Path.home() / ".claude" / "skills" / skill).is_dir():
            d.ok(f"스킬 {skill}")
        else:
            d.fail(f"스킬 {skill}", f"~/.claude/skills/{skill} 없음", "autotdd 설치 확인")


def run_pings(d: Doctor, names: list[str], wrapper_dir: Path) -> None:
    """③' --ping: 후보 래퍼의 ping-<래퍼명> 실행 (크레딧 소모 경고 선출력)."""
    print("⚠ --ping: 실제 LLM 호출로 크레딧이 소모될 수 있습니다 — 진행합니다")
    for name in names:
        ping = wrapper_dir / f"ping-{name}.sh"
        if not ping.is_file():
            ping = WRAPPER_DEFAULT_DIR / f"ping-{name}.sh"
        if not ping.is_file():
            d.fail(f"ping-{name}", f"{ping} 없음", "autotdd 설치 확인")
            continue
        rc, out, err, timed_out = core.run_with_timeout(["bash", str(ping)], 180)
        if out.strip():
            print(out.strip())
        if err.strip():
            print(err.strip())
        if timed_out or rc != 0:
            d.fail(f"ping-{name}", "응답 이상 (위 출력 참조)", f"bash {ping} 단독 실행으로 확인")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Repository root path")
    parser.add_argument(
        "--ping", action="store_true",
        help="후보 래퍼의 ping-<래퍼명>도 실행 (크레딧 소모 가능; 기본 미실행)",
    )
    args = parser.parse_args()
    repo = Path(args.repo).resolve()

    spec = os.environ.get("AUTOQAFIX_WRAPPERS", WRAPPERS_DEFAULT)
    names = list(autofix.parse_wrapper_spec(spec))
    wrapper_dir = Path(os.environ.get("AUTOQAFIX_WRAPPER_DIR", str(WRAPPER_DEFAULT_DIR)))

    d = Doctor()
    check_preflight(d, repo)
    check_wrappers(d, names, wrapper_dir)
    check_usage_scripts(d, names)
    check_select_llm(d, names)
    check_deploy(d, repo)
    check_lock(d, repo)
    check_skills(d)
    if args.ping:
        run_pings(d, names, wrapper_dir)

    print(f"진단 완료: FAIL {d.fails}건")
    return d.fails


if __name__ == "__main__":
    sys.exit(main())
