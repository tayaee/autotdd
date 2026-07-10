#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

# autoqafix_core.py와 같은 위치이므로 임포트 가능
import autoqafix_core as core

def find_repo_relative_path(file_path_str, repo_path):
    p = Path(file_path_str)
    repo_resolved = repo_path.resolve()
    if p.is_absolute():
        try:
            resolved_p = p.resolve()
            if resolved_p.is_relative_to(repo_resolved):
                return str(resolved_p.relative_to(repo_resolved))
        except Exception:
            pass
    else:
        # 상대 경로인 경우
        if (repo_path / p).exists():
            return str(p)
        parts = p.parts
        for i in range(1, len(parts)):
            sub_p = Path(*parts[i:])
            if (repo_path / sub_p).exists():
                return str(sub_p)
    return None

def extract_timestamp(line):
    m = re.match(r'^(\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}(?:[,\.]\d+)?(?:[+-]\d{2}:?\d{2})?)', line.strip())
    if m:
        return m.group(1)
    return ""

def truncate_excerpt(excerpt):
    excerpt_bytes = excerpt.encode('utf-8')
    if len(excerpt_bytes) > 16384:
        truncated = excerpt_bytes[:16384]
        return truncated.decode('utf-8', errors='ignore') + "...[truncated]"
    return excerpt

def normalize_message(msg):
    # 1. 따옴표 내용 제거
    msg = re.sub(r"'.*?'", "", msg)
    msg = re.sub(r'".*?"', "", msg)
    # 2. 숫자열 -> #
    msg = re.sub(r"\d+", "#", msg)
    # 3. 공백 축약
    msg = " ".join(msg.split())
    return msg

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=str, help="Repository root path")
    parser.add_argument("--state-dir", type=str, default=None, help="Directory to save offsets.json")
    parser.add_argument("--dry-run", action="store_true", help="Do not update offsets.json")
    args = parser.parse_args()

    repo_path = Path(args.repo).resolve()
    if args.state_dir:
        state_dir = Path(args.state_dir).resolve()
    else:
        state_dir = core.state_dir(repo_path)
    state_dir.mkdir(parents=True, exist_ok=True)
    offsets_json_path = state_dir / "offsets.json"

    # 오프셋 로드
    offsets_data = {}
    if offsets_json_path.exists():
        try:
            with open(offsets_json_path, "r", encoding="utf-8") as f:
                offsets_data = json.load(f)
        except Exception:
            pass

    logs_dir = repo_path / "logs"
    log_files = []
    if logs_dir.is_dir():
        log_files = sorted([f for f in logs_dir.glob("*.log") if f.is_file()])

    new_offsets = {}
    all_scanned_errors = []

    for filepath in log_files:
        filename = filepath.name
        # 1KB prefix 구하기
        try:
            with open(filepath, "rb") as f:
                prefix_bytes = f.read(1024)
        except Exception:
            prefix_bytes = b""
        prefix_len = len(prefix_bytes)
        prefix_sha1 = hashlib.sha1(prefix_bytes).hexdigest()
        
        try:
            size = filepath.stat().st_size
        except Exception:
            size = 0

        # 기존 상태 조회
        state = offsets_data.get(filename)
        if state is None:
            # 첫 관측 파일
            new_offsets[filename] = {
                "prefix_sha1": prefix_sha1,
                "prefix_len": prefix_len,
                "size": size,
                "offset": size
            }
            continue

        old_prefix_sha1 = state.get("prefix_sha1")
        old_prefix_len = state.get("prefix_len")
        old_offset = state.get("offset", 0)

        is_new_file = False
        if prefix_sha1 != old_prefix_sha1 or prefix_len != old_prefix_len:
            is_new_file = True
        elif size < old_offset:
            is_new_file = True

        if is_new_file:
            start_offset = 0
        else:
            start_offset = old_offset

        # 새 구간이 10MB 초과하는 경우
        new_bytes = size - start_offset
        if new_bytes > 10 * 1024 * 1024:
            skipped = new_bytes - 10 * 1024 * 1024
            start_offset += skipped
            print(f"Warning: skipped {skipped} bytes in {filename}", file=sys.stderr)

        # 파일 라인 읽기
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                all_lines = f.readlines()
        except Exception:
            all_lines = []

        # 라인별 시작 오프셋 계산
        line_offsets = []
        curr_offset = 0
        for line in all_lines:
            line_offsets.append(curr_offset)
            curr_offset += len(line.encode('utf-8'))

        # start_offset에 대응하는 라인 인덱스 구하기
        start_line_idx = len(all_lines)
        for idx, offset in enumerate(line_offsets):
            if offset >= start_offset:
                start_line_idx = idx
                break

        # 파일 전체에 대한 에러 추출
        errors_found = []
        i = 0
        while i < len(all_lines):
            line = all_lines[i]
            if "Traceback (most recent call last):" in line:
                tb_start_idx = i
                tb_end_idx = i
                j = i + 1
                while j < len(all_lines):
                    next_line = all_lines[j]
                    if next_line.strip() == "":
                        j += 1
                        continue
                    if not next_line.startswith(" ") and not next_line.startswith("\t"):
                        tb_end_idx = j
                        break
                    j += 1
                else:
                    tb_end_idx = len(all_lines) - 1

                tb_lines = all_lines[tb_start_idx : tb_end_idx + 1]
                
                # 직전 타임스탬프 라인 찾기
                latest_ts = ""
                for k in range(tb_start_idx, -1, -1):
                    ts = extract_timestamp(all_lines[k])
                    if ts:
                        latest_ts = ts
                        break

                # 예외 타입 구하기
                exception_line = all_lines[tb_end_idx].strip()
                exc_match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)(?::\s*(.*))?$', exception_line)
                exc_type = exc_match.group(1) if exc_match else "Exception"

                # 최심 프레임 찾기
                relative_path = None
                line_no = "0"
                for k in range(tb_end_idx - 1, tb_start_idx, -1):
                    frame_line = all_lines[k]
                    m = re.search(r'File\s+["\'](.+?)["\'],\s+line\s+(\d+)', frame_line)
                    if m:
                        file_path_str = m.group(1)
                        lineno_str = m.group(2)
                        rel = find_repo_relative_path(file_path_str, repo_path)
                        if rel:
                            relative_path = rel
                            line_no = lineno_str
                            break
                if relative_path is None:
                    # repo 내부 프레임이 없으면 가장 아래 프레임 그냥 사용
                    for k in range(tb_end_idx - 1, tb_start_idx, -1):
                        frame_line = all_lines[k]
                        m = re.search(r'File\s+["\'](.+?)["\'],\s+line\s+(\d+)', frame_line)
                        if m:
                            relative_path = m.group(1)
                            line_no = m.group(2)
                            break
                    if relative_path is None:
                        relative_path = "unknown"

                dedup_key = f"tb:{relative_path}:{line_no}:{exc_type}"

                # excerpt 구하기 (앞뒤 10줄)
                pre_start = max(0, tb_start_idx - 10)
                post_end = min(len(all_lines), tb_end_idx + 1 + 10)
                excerpt = "".join(all_lines[pre_start : post_end])
                excerpt = truncate_excerpt(excerpt)

                errors_found.append({
                    "dedup_key": dedup_key,
                    "latest_ts": latest_ts,
                    "excerpt": excerpt,
                    "line_idx": tb_end_idx,
                    "logfile": filename
                })
                i = tb_end_idx + 1
            else:
                level_match = re.search(r'\[(ERROR|CRITICAL)\]', line)
                if level_match:
                    # 바로 다음이나 그 다음 줄에 Traceback이 나오는지 확인 (traceback의 헤더로 간주하여 중복 수집 방지)
                    is_tb_header = False
                    for check_idx in range(i + 1, min(len(all_lines), i + 3)):
                        if "Traceback (most recent call last):" in all_lines[check_idx]:
                            is_tb_header = True
                            break
                    
                    if not is_tb_header:
                        # 일반 에러 라인
                        latest_ts = extract_timestamp(line)
                        after_level = line[level_match.end():].strip()
                        
                        logger = "root"
                        message = after_level
                        m = re.match(r'^([^\s\-]+)\s*-\s*(.*)$', after_level)
                        if m:
                            logger = m.group(1)
                            message = m.group(2)

                        normalized = normalize_message(message)
                        normalized_hash = hashlib.sha1(normalized.encode('utf-8')).hexdigest()[:8]
                        dedup_key = f"line:{filename}:{logger}:{normalized_hash}"

                        pre_start = max(0, i - 10)
                        post_end = min(len(all_lines), i + 1 + 10)
                        excerpt = "".join(all_lines[pre_start : post_end])
                        excerpt = truncate_excerpt(excerpt)

                        errors_found.append({
                            "dedup_key": dedup_key,
                            "latest_ts": latest_ts,
                            "excerpt": excerpt,
                            "line_idx": i,
                            "logfile": filename
                        })
                i += 1

        # 이번 스캔 구간 내에 있는 에러 필터링
        scanned = [err for err in errors_found if err["line_idx"] >= start_line_idx]
        all_scanned_errors.extend(scanned)

        # 새 오프셋 설정 기록
        new_offsets[filename] = {
            "prefix_sha1": prefix_sha1,
            "prefix_len": prefix_len,
            "size": size,
            "offset": size
        }

    # 결과 취합 및 dedup_key 별 그룹화
    grouped = {}
    for err in all_scanned_errors:
        key = err["dedup_key"]
        if key not in grouped:
            grouped[key] = {
                "dedup_key": key,
                "count": 0,
                "errors": []
            }
        grouped[key]["count"] += 1
        grouped[key]["errors"].append(err)

    result_errors = []
    for key, data in grouped.items():
        latest_err = max(data["errors"], key=lambda x: x["line_idx"])
        ts_list = [e["latest_ts"] for e in data["errors"] if e["latest_ts"]]
        latest_ts = max(ts_list) if ts_list else latest_err["latest_ts"]

        result_errors.append({
            "dedup_key": key,
            "count": data["count"],
            "excerpt": latest_err["excerpt"],
            "latest_ts": latest_ts,
            "logfile": latest_err["logfile"]
        })

    # 정렬 및 100개 상한
    result_errors.sort(key=lambda x: (-x["count"], x["dedup_key"]))
    result_errors = result_errors[:100]

    # window 계산
    all_ts = [err["latest_ts"] for err in all_scanned_errors if err["latest_ts"]]
    window_start = min(all_ts) if all_ts else ""
    window_end = max(all_ts) if all_ts else ""

    output_json = {
        "errors": result_errors,
        "window": {
            "start": window_start,
            "end": window_end
        }
    }

    # stdout에 JSON 출력
    print(json.dumps(output_json))

    # dry-run이 아니면 오프셋 데이터 파일 업데이트
    if not args.dry_run:
        for fn, info in new_offsets.items():
            offsets_data[fn] = info
        with open(offsets_json_path, "w", encoding="utf-8") as f:
            json.dump(offsets_data, f, indent=2)

if __name__ == "__main__":
    main()
