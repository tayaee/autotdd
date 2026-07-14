#!/usr/bin/env bash
# install.sh — issue-21: 트리거 스킬 4종을 ~/.claude/skills/로 symlink 설치 (idempotent).
#
# 설치 대상 (4종):
#   .claude/skills/autoqa     — 트리거 /autoqa
#   .claude/skills/autofix    — 트리거 /autofix
#   .claude/skills/autodev    — 트리거 /autodev
#   .claude/skills/autoqafix  — 엔진 폴더 + 트리거 /autoqafix 겸용
#
# 2회 이상 실행해도 항상 같은 상태 (이미 존재하는 링크는 건너뜀).
# 깨진(대상이 사라진) symlink는 자동으로 $src에 재연결한다.
set -euo pipefail

# 이 스크립트가 있는 곳의 절대경로 = repo 루트.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/skills"

# HOME이 지정돼 있으면 그쪽, 아니면 현재 사용자 HOME.
HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6 2>/dev/null || echo ~)}"
DST_DIR="$HOME_DIR/.claude/skills"

mkdir -p "$DST_DIR"

installed=0
skipped=0
missing=0

for skill in autoqa autofix autodev autoqafix; do
    src="$SRC_DIR/$skill"
    dst="$DST_DIR/$skill"

    if [ ! -d "$src" ]; then
        echo "WARN: $src 없음 — 건너뜀" >&2
        missing=$((missing + 1))
        continue
    fi

    if [ -L "$dst" ]; then
        if [ -e "$dst" ]; then
            # symlink가 존재하고 대상도 resolve됨 → 그대로 둠 (idempotent 핵심)
            target="$(readlink "$dst")"
            echo "이미 설치됨 (symlink): $dst → $target"
            skipped=$((skipped + 1))
            continue
        fi
        # symlink이지만 대상이 사라짐 (dangling) → 제거 후 $src로 재연결.
        # 삭제 대상은 -L 판정된 링크 자체뿐 — 일반 파일/디렉토리는 절대 삭제하지 않는다.
        rm -f "$dst"
        ln -s "$src" "$dst"
        echo "재연결(깨진 링크 복구): $dst → $src"
        installed=$((installed + 1))
        continue
    fi

    if [ -e "$dst" ]; then
        # 심볼릭 링크도 아니고 이미 뭔가 있음 (디렉토리/파일 등) → 덮어쓰지 않음
        echo "WARN: $dst 가 symlink가 아닌 채로 존재 — 건너뜀 (수동 정리 필요)" >&2
        missing=$((missing + 1))
        continue
    fi

    ln -s "$src" "$dst"
    echo "설치: $dst → $src"
    installed=$((installed + 1))
done

echo "—"
echo "install 요약: 새로 설치 $installed, 이미 설치됨 $skipped, 건너뜀(누락/충돌) $missing"
# 새로 설치했어도, 누락/충돌 경고가 있으면 nonzero로 알려준다.
if [ "$missing" -gt 0 ]; then
    exit 1
fi
exit 0