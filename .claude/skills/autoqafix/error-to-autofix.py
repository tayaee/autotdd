#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# autoqafix_core.py와 같은 위치이므로 임포트 가능
import autoqafix_core as core

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=str, help="Repository root path")
    args = parser.parse_args()

    repo_path = Path(args.repo).resolve()

    # AUTOQAFIX_WRAPPERS 파싱
    spec = os.environ.get("AUTOQAFIX_WRAPPERS", "claudecli:paid,minimaxcli:paid,qwencli:local")
    tiers = {}
    for entry in spec.split(","):
        entry = entry.strip()
        if not entry:
            continue
        name, _, tier = entry.partition(":")
        name = name.strip()
        tier = tier.strip()
        if name and tier:
            tiers[name] = tier

    # select-llm 호출
    select_llm_path = Path(__file__).parent / "select-llm.py"
    try:
        proc = subprocess.run(["python3", str(select_llm_path)], capture_output=True, text=True, timeout=30)
        selected_llm = proc.stdout.strip()
    except Exception as e:
        selected_llm = "none"

    selected_tier = tiers.get(selected_llm, "local")

    # 유료 LLM 부적격 검증
    if selected_llm == "none" or selected_tier == "local":
        print("유료 LLM 부적격, 보고 연기")
        # 오프셋 비전진: log-scan을 --dry-run으로 실행
        log_scan_path = Path(__file__).parent / "log-scan.py"
        subprocess.run(["python3", str(log_scan_path), "--repo", str(repo_path), "--dry-run"], capture_output=True)
        sys.exit(0)

    # 1단계: 에러 스캔 (dry-run)
    log_scan_path = Path(__file__).parent / "log-scan.py"
    proc = subprocess.run(["python3", str(log_scan_path), "--repo", str(repo_path), "--dry-run"], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(1)

    try:
        scan_result = json.loads(proc.stdout)
    except Exception:
        scan_result = {"errors": [], "window": {"start": "", "end": ""}}

    errors = scan_result.get("errors", [])
    window = scan_result.get("window", {"start": "", "end": ""})

    # 2단계: 중복 제거 (dedup)
    issues_dir = repo_path / "issues"
    dedup_keys_in_issues = set()
    if issues_dir.is_dir():
        # issues/ 하위 바로 밑에 있는 .md 파일만 조회 (archive 폴더 제외)
        for f in issues_dir.glob("*.md"):
            if f.is_file():
                try:
                    content = f.read_text(encoding="utf-8", errors="ignore")
                    for line in content.splitlines():
                        if "dedup-key:" in line:
                            _, _, key = line.partition("dedup-key:")
                            dedup_keys_in_issues.add(key.strip())
                except Exception:
                    pass

    remaining_errors = [err for err in errors if err["dedup_key"] not in dedup_keys_in_issues]
    targets = remaining_errors[:5]

    wrapper_dir = Path(os.environ.get("AUTOQAFIX_WRAPPER_DIR", Path(__file__).parent / "wrappers"))
    wrapper_path = wrapper_dir / f"{selected_llm}.sh"
    light_timeout = int(os.environ.get("AUTOQAFIX_LIGHT_TIMEOUT", "1200"))

    all_success = True
    processed_count = 0

    for err in targets:
        dedup_key = err["dedup_key"]
        count = err["count"]
        excerpt = err["excerpt"]
        latest_ts = err["latest_ts"]
        logfile = err["logfile"]

        # 프롬프트 조립
        prompt = (
            f"에러 발생 횟수: {count}\n"
            f"최신 발생 시각: {latest_ts}\n"
            f"로그 파일명: {logfile}\n"
            f"에러 로그 발췌:\n{excerpt}\n\n"
            f"지시사항:\n"
            f"배경/요구사항/승인 기준 3섹션 형식의 한국어 issue 본문과 첫 줄 제목, 그리고 agent-tier(local-ok|paid-only|manual) 판정을 출력하라. 마지막 줄은 `TIER: <값>`"
        )

        # 래퍼 호출
        cmd = ["bash", str(wrapper_path), "-p", prompt]
        rc, out, _, timed_out = core.run_with_timeout(cmd, light_timeout)

        if timed_out or rc != 0:
            all_success = False
            continue

        lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
        if not lines:
            all_success = False
            continue

        # TIER 파싱
        tier = "manual"
        tier_found = False
        for line in reversed(lines):
            m = re.match(r'^TIER:\s*(\S+)', line)
            if m:
                tier = m.group(1).lower()
                tier_found = True
                break

        if tier not in ("local-ok", "paid-only", "manual"):
            tier = "manual"

        # 제목 파싱
        title_line = lines[0]
        summary = title_line
        if title_line.startswith("#"):
            m = re.match(r'^#\s*\S+:\s*(.*)$', title_line)
            if m:
                summary = m.group(1).strip()
            else:
                summary = title_line.lstrip("#").strip()

        # 래퍼 본문 파싱 (제목과 TIER 제외)
        raw_lines = out.splitlines()
        body_content_lines = []
        for idx, rline in enumerate(raw_lines):
            if idx == 0:
                continue
            if "TIER:" in rline:
                continue
            body_content_lines.append(rline)
        wrapper_body = "\n".join(body_content_lines).strip()

        # 번호 예약
        try:
            n, filepath = core.reserve_number(repo_path, "autofix", summary, "error-to-autofix")
        except Exception:
            all_success = False
            continue

        # 최종 본문 결합
        window_str = f"{window.get('start', '')} ~ {window.get('end', '')}"
        body = (
            f"dedup-key: {dedup_key}\n"
            f"agent-tier: {tier}\n"
            f"frequency: {count} ({window_str})\n\n"
            f"{wrapper_body}\n\n"
            f"## 로그 발췌\n\n"
            f"```log\n{excerpt}\n```\n\n"
            f"[주의] 로그 원문(logs/)을 열지 말 것 — 필요한 발췌는 이 문서에 포함됨.\n"
        )

        try:
            core.finalize_item(repo_path, filepath, body)
        except Exception:
            all_success = False
            continue

        # manual 처리
        if tier == "manual":
            try:
                new_filename = f"autofix-{n}-manual.md"
                new_filepath = filepath.parent / new_filename
                core._git(repo_path, "mv", str(filepath.relative_to(repo_path)), str(new_filepath.relative_to(repo_path)))
                core._git(repo_path, "commit", "-q", "-m", f"autofix-{n}-manual: {summary}")
                core._git(repo_path, "push")
            except Exception:
                all_success = False
                continue

        processed_count += 1

    # 오프셋 전진
    if len(targets) > 0 and all_success and processed_count == len(targets):
        subprocess.run(["python3", str(log_scan_path), "--repo", str(repo_path)], capture_output=True)

if __name__ == "__main__":
    main()
