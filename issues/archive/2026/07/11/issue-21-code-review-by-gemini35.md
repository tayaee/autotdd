# PR Code Review: Issue-21 Claude Code 트리거 스킬 4종 및 install.sh 구현 감사

본 문서는 [issue-21.md](file:///home/user1/git/autotdd/issues/archive/2026/07/11/issue-21.md)의 구현 결과에 대한 코드 품질 감사(Code Quality Audit) 결과를 정리한 PR 리뷰입니다.

## 1. 개요 (Overview)
- **대상 이슈**: [issue-21.md](file:///home/user1/git/autotdd/issues/archive/2026/07/11/issue-21.md)
- **최신 커밋**: `0cf8961d571fb46d1e9d44f608c0a24096a15ea9` (issue-21: Claude Code 트리거 스킬 4종 (autoqa/autofix/autodev/autoqafix) + install.sh)
- **검토 대상 파일**:
  - [install.sh](file:///home/user1/git/autotdd/install.sh)
  - [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)
  - [.claude/skills/autodev/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autodev/SKILL.md)
  - [.claude/skills/autofix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autofix/SKILL.md)
  - [.claude/skills/autoqa/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqa/SKILL.md)
  - [.claude/skills/autoqafix/SKILL.md](file:///home/user1/git/autotdd/.claude/skills/autoqafix/SKILL.md)

---

## 2. 주요 강점 (Strengths)

### 2.1. 멱등성(Idempotency)이 보장된 설치 스크립트
- [install.sh](file:///home/user1/git/autotdd/install.sh)는 설치 작업을 반복 수행해도 동일한 상태를 유지하도록 설계되었습니다.
- 심볼릭 링크가 이미 존재하는지 (`[ -L "$dst" ]`), 일반 파일이나 디렉토리 형태로 동일한 이름이 충돌하는지 (`[ -e "$dst" ]`) 사전에 판단하여 덮어쓰기 사고를 예방하고 적절히 건너뜁니다.
- 설치 상태 요약(새로 설치, 스킵, 건너뜀)을 깔끔하게 출력하여 실행 결과를 직관적으로 이해할 수 있습니다.

### 2.2. 고도로 격리된 리그레션 테스트 작성
- [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)는 실제 개발자의 `HOME` 환경을 침범하지 않도록 `mktemp -d`를 통해 가짜 홈 디렉토리를 구축하고, `HOME="$fake_home"` 환경 변수 주입을 통해 테스트를 수행합니다.
- `trap cleanup EXIT` 구문을 활용해 테스트 중 실패가 발생하더라도 생성된 임시 디렉토리를 안전하게 제거합니다.
- 설치 스크립트의 1차, 2차 실행을 모두 시뮬레이션하여 멱등성과 4종의 심볼릭 링크 정상 생성 여부를 완벽하게 확인합니다.

### 2.3. 요건을 성실히 반영한 SKILL.md 구성
- 각 스킬 파일(4종)은 요구사항에 제시된 frontmatter 문법(`---`), name/description 필드 구성, 그리고 본문 내 핵심 규칙(예: `smarthome`과의 독립성, 스킬 자체의 이슈 작성 및 코드 수정 금지 정책)을 정확히 문서화하여 명시하고 있습니다.

---

## 3. 개선 가능 영역 및 권장 사항 (Improvement Areas & Recommendations)

### 3.1. [install.sh](file:///home/user1/git/autotdd/install.sh)

#### 1) 예기치 못한 에러 대응을 위한 `set -e` 추가 권장
- 현재 스크립트 상단에 `set -uo pipefail`만 정의되어 있어, 중간 과정(예: `mkdir -p` 실패 또는 `ln -s` 실패)에서 에러가 발생해도 스크립트가 중단되지 않고 `exit 0`으로 끝나거나 멱등성 집계 수치가 잘못 표기될 수 있습니다.
- **권장 조치**: `set -euo pipefail`로 전환하여 런타임 실패가 있을 시 즉시 중단되도록 보완할 것을 권장합니다.

#### 2) 프로젝트 위치 이동 시 깨짐 방지를 위한 상대경로 심볼릭 링크 제안
- 현재는 `REPO_ROOT`를 절대경로로 구하여 `ln -s "$src" "$dst"` 형태로 절대경로 심볼릭 링크를 생성합니다. 이 방식은 프로젝트 디렉토리를 이동하게 되면 기존에 생성된 `~/.claude/skills/*` 링크가 깨지게 됩니다.
- **권장 조치**: `ln -s`를 사용할 때 상대 경로 방식으로 링크를 생성하는 것을 고려할 수 있습니다. (다만 사용 환경의 `ln` 버전에 따라 `--relative` 옵션 지원 여부가 다를 수 있으므로 absolute path가 가장 안전한 fallback이 될 수는 있습니다.)

#### 3) 강제 재설치(Force) 옵션 제공 검토
- 타사/타 프로젝트의 스킬이 동일한 이름으로 `~/.claude/skills/`에 잡혀 있는 경우, 현재는 `missing`으로 처리하고 건너뜁니다.
- **권장 조치**: 사용자가 강제로 이 레포의 스킬로 덮어쓰고자 할 때를 대비해 `-f` 또는 `--force` 플래그를 받아 기존 링크/파일을 지우고 덮어쓰는 기능을 추가하면 편의성이 한층 올라갈 것입니다.

---

### 3.2. [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)

#### 1) 무의미한 기본값 지정 및 미완성 검증 로직 개선
- **144번 라인**: `real_home_skills="${HOME:-$HOME}/.claude/skills"`에서 `${HOME:-$HOME}`은 문법상 무의미합니다.
- **145~151번 라인**: 실제 호스트의 `HOME`이 오염되지 않았는지 확인하는 루프인데, 내부에 실질적인 검증(Assertion) 코드가 없으며 단지 `:` (noop) 처리가 되어 있어 껍데기만 남아 있습니다.
  ```bash
  for skill in autoqa autofix autodev autoqafix; do
      if [ -e "$real_home_skills/$skill" ]; then
          # 실제 HOME에 같은 이름이 있어도, 그것이 방금 만든 게 아니면 OK.
          # 이 테스트는 "가짜 HOME만 변경됐는지" 확인한다.
          :
      fi
  done
  ```
- **권장 조치**: 실제로 `fake_home`에 대한 설치가 실 HOME에 영향을 주지 않았는지 명확히 검증하는 검사식을 추가하거나, 불필요한 빈 루프를 제거하여 코드를 단순화하는 것이 좋습니다.

#### 2) 중복적인 스크립트 실행 제거
- **112~113번 라인**:
  ```bash
  rc1="$(HOME="$fake_home" bash "$INSTALL_SH" >/dev/null 2>&1; echo $?)"
  rc2="$(HOME="$fake_home" bash "$INSTALL_SH" >/dev/null 2>&1; echo $?)"
  ```
  이미 92번 라인(1차 실행)과 106번 라인(2차 실행)에서 `install.sh`를 호출했음에도, exit code를 한 번 더 구하기 위해 3차, 4차 실행을 반복하고 있습니다.
- **권장 조치**: 92번과 106번 실행의 종료 코드(`$?`)를 각각 `rc1`, `rc2` 변수에 담아두고 이후 검증에서 재사용하도록 수정하면 불필요한 중복 실행을 줄이고 테스트 속도를 향상시킬 수 있습니다.

#### 3) 한글 검증용 정규식 제약 사항
- **68번 라인**: `grep -qE '금지|하지 말|쓰지 말|고치지 말|하지마' "$path"`
  한국어 설명에만 의존하는 정규식 필터입니다. 만약 향후에 타 언어 지원이나 영문 번역이 도입된다면 본 테스트는 아무런 수정 없이도 오작동(Fail)하게 됩니다.
- **권장 조치**: 영문 표현(`prohibit`, `forbid`, `must not`, `do not`) 등도 함께 매칭할 수 있도록 정규식을 보완하거나, 테스트 대상 문서의 다국어 여부를 고려할 필요가 있습니다.

---

## 4. 종합 결론 (Conclusion)
`issue-21`의 전체적인 구현 수준은 요구사항และ 인수 조건을 완벽하게 만족하고 있으며, 리그레션 테스트까지 격리된 환경에서 성실하게 작성되어 매우 훌륭합니다.

다만, [regression-tests/verify-issue-21.sh](file:///home/user1/git/autotdd/regression-tests/verify-issue-21.sh)의 실 HOME 오염 미검증(빈 루프) 부분이나 [install.sh](file:///home/user1/git/autotdd/install.sh)의 에러 핸들링(`set -e`) 미비 등 마이너한 개선점들이 존재하므로, 이를 보완한 뒤 병합(Merge)하는 것을 권장합니다.
