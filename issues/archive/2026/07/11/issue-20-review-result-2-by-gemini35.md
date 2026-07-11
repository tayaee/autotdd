# Issue 20 Code Quality Audit & Review Result

본 문서는 `issue-20` (사전 점검 도구 `autoqafix-doctor`) 구현과 관련된 Git 로그 및 소스 코드를 감사(Audit)하여 발견된 미비점, 아키텍처적 불일치, OS 이식성 결여 및 "고칠 때 같이 고쳤어야 하는 안일한 대응" 등을 정리한 코드 품질 리뷰 보고서입니다.

---

## 1. 감사 대상 정보

- **대상 이슈**: [issue-20: autoqafix-doctor — 사전 점검 도구](file:///home/user1/git/autotdd/issues/archive/2026/07/11/issue-20.md)
- **주요 커밋**: `029ce34` ("issue-20: autoqafix-doctor — 사전 점검 도구 (preflight 상위 집합 ...)")
- **주요 점검 파일**:
  1. [.claude/skills/autoqafix/autoqafix-doctor.py](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py)
  2. [autoqafix_core.py](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix_core.py)
  3. [select-llm.py](file:///home/user1/git/autotdd/.claude/skills/autoqafix/select-llm.py)
  4. [autoqafix-doctor.sh](file:///home/user1/git/autotdd/autoqafix-doctor.sh), [autoqafix-doctor.bat](file:///home/user1/git/autotdd/autoqafix-doctor.bat), [autoqafix-doctor.ps1](file:///home/user1/git/autotdd/autoqafix-doctor.ps1)

---

## 2. 주요 미비점 및 개선 필요 사항 (코드 감사 결과)

### ① 필수 스킬 중복 검사 및 목록 불일치 (Redundancy & Inconsistency)
- **발견된 문제**:
  - `autoqafix-doctor.py` 내의 [check_preflight](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L61-L70) 함수는 `core.preflight("fix", repo)`를 간접 호출합니다.
  - [autoqafix_core.py](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix_core.py#L92-L96)의 `preflight` 내에서는 `role in ("fix", "dev")` 일 때 이미 `autotdd`, `tdd2`, `acpd` 스킬 폴더 존재 여부를 검사하고 에러를 누적합니다.
  - 그러나 `autoqafix-doctor.py`는 뒤이어 [check_skills](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L161-L168) 함수를 호출하여 동일한 `autotdd`, `tdd2`, `acpd`를 한 번 더 체크하며, 여기에 `tdd`를 추가하여 총 4종의 스킬을 검사합니다.
- **영향**:
  - 스킬이 설치되지 않은 환경에서 사전 진단을 돌릴 경우, 동일한 스킬 부재에 대해 FAIL 카운트가 **중복 계수**되어 실제 실패한 진단 항목 수보다 더 큰 exit code 값을 반환하게 됩니다.
  - 또한, `core.preflight` 내부에서는 필수 스킬로 `tdd`가 정의되어 있지 않은 반면, `autoqafix-doctor.py`에서는 `tdd`를 `REQUIRED_SKILLS`에 포함하고 있어 **필수 스킬 정의에 대한 일관성**이 결여되어 있습니다.

---

### ② usage 스크립트 실행의 오버헤드와 중복 기동 (Performance Redundancy)
- **발견된 문제**:
  - `autoqafix-doctor.py`는 [check_usage_scripts](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L88-L109)에서 `AUTOQAFIX_WRAPPERS`에 지정된 후보 래퍼들의 `usage-<래퍼명>.py`를 각각 `uv -q run`으로 기동하고 유효 JSON인지 확인합니다.
  - 하지만 바로 뒤이어 실행되는 [check_select_llm](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L111-L128)에서는 `select-llm.py`를 기동하며, 이 `select-llm.py` 내부에서도 [fetch_usage](file:///home/user1/git/autotdd/.claude/skills/autoqafix/select-llm.py#L57-L79)를 거쳐 **동일한 usage 스크립트들을 다시 한 번 `uv -q run`으로 중복 실행**합니다.
- **영향**:
  - 로컬 진단 도구임에도 불구하고 무거운 프로세스 기동이 중복되어 전체 수행 속도가 크게 저하됩니다. (최대 타임아웃의 합이 수 분에 달함)
  - "고칠 때 같이 고쳤어야 하는 안일함"으로 지적될 수 있는 부분으로, `select-llm.py`가 usage 결과를 캐싱하거나, 혹은 doctor가 확인한 usage 데이터를 파라미터나 환경변수로 주입받아 오버헤드를 회피하도록 결합도를 조정하지 않은 설계적 나태함이 보입니다.

---

### ③ `run_pings`에서 `--ping` 옵션 처리 시 플랫폼(OS) 이식성 결여 (OS Portability Issue)
- **발견된 문제**:
  - `autoqafix-doctor`는 크로스 플랫폼을 지향하며 Windows 환경을 위해 `autoqafix-doctor.bat` 및 `autoqafix-doctor.ps1` 런처를 모두 추가로 제공했습니다.
  - 그러나 파이썬 스크립트 내부의 [run_pings](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L170-L187) 함수를 보면, 실행 파라미터로 `["bash", str(ping)]`을 하드코딩하고 있으며, 검색 대상 역시 오로지 `ping-{name}.sh` 확장자만 보고 있습니다.
- **영향**:
  - 일반 Windows 환경(WSL 미사용)에서 `autoqafix-doctor`를 구동하고 `--ping` 옵션을 인자로 넘길 경우, `bash` 명령이 존재하지 않아 스크립트 자체가 `FileNotFoundError`로 비정상 종료됩니다.
  - 또한 Windows용 핑 파일인 `ping-{name}.bat` 이나 `ping-{name}.ps1` 파일이 존재하더라도 감지 및 기동하지 못하므로, 윈도우 런처 포팅 작업 대비 내부 구현의 이식성 고려 수준이 턱없이 부족한 상태로 방치되었습니다.

---

### ④ `check_lock`과 `core.acquire_lock` 간의 stale 잠금 판정 조건 불일치 (Divergent Stale Mutex Logic)
- **발견된 문제**:
  - [autoqafix_core.py:acquire_lock](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix_core.py#L132-L165) 락 획득 로직에서는 락 파일이 존재하더라도 **(1) 소유 PID 사망(동일 호스트)** 혹은 **(2) 락이 생성된 지 4시간 이상(stale_sec 초과)** 된 경우 'stale lock'으로 간주하여 잠금을 무시하고 재획득할 수 있습니다.
  - 하지만 `autoqafix-doctor.py`의 [check_lock](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L143-L159) 진단 함수는 오직 소유 PID 사망(`pid_dead`) 여부만 검사하여 OK 판정을 내립니다.
- **영향**:
  - 만약 생성된 지 4시간이 지나 획득이 가능한 상태(`is_stale`)의 락 파일이 남아있을 때, 실제 자동화 루프(`acquire_lock`)는 아무 문제 없이 락을 얻고 동작함에도 불구하고, 사전 진단 스크립트인 `autoqafix-doctor`는 해당 잠금을 '살아있는 것'으로 오판하여 `FAIL 뮤텍스 잠금`을 출력하는 오작동 시나리오가 발생합니다.

---

### ⑤ `deploy` 스크립트 탐색 시 단순 파일 존재 여부만 검사 (Missing Executable Checks)
- **발견된 문제**:
  - [check_deploy](file:///home/user1/git/autotdd/.claude/skills/autoqafix/autoqafix-doctor.py#L130-L141) 함수는 대상 저장소 루트에 배포 스크립트가 존재하는지 판단하기 위해 `is_file()` 존재 여부만 체크합니다.
- **영향**:
  - POSIX 호환 환경에서는 `deploy.sh` 파일이 디렉토리에 존재하더라도 실행 권한(`chmod +x`)이 유효하지 않으면 동작하지 않습니다.
  - 단순히 파일이 존재함을 검사하는 데 그치지 않고, `os.access(path, os.X_OK)` 등을 통해 실행 가능한 스크립트인지를 부가 검증하는 꼼꼼함이 결여되었습니다.

---

### ⑥ Windows 런처 내의 부적절한 오류 해결 조치 가이드 제공 (Windows Host Action Recommendations)
- **발견된 문제**:
  - Windows CMD 환경용 [autoqafix-doctor.bat](file:///home/user1/git/autotdd/autoqafix-doctor.bat#L5) 및 PowerShell용 [autoqafix-doctor.ps1](file:///home/user1/git/autotdd/autoqafix-doctor.ps1) 런처에서 `uv`가 잡히지 않을 때의 대처 조치 가이드로 `curl -LsSf https://astral.sh/uv/install.sh | sh`라는 리눅스 셸 전용 설치 스크립트 명령어를 하드코딩하여 제시하고 있습니다.
- **영향**:
  - Windows의 명령 프롬프트나 파워셸 콘솔에서 조치 사항에 나온 명령을 그대로 복사해 실행할 경우 정상 동작하지 않거나 오류가 납니다.
  - Windows 환경의 사용자를 위해서는 파워셸 스크립트 내에서 `irm https://astral.sh/uv/install.ps1 | iex` 또는 공식 문서 링크 등을 적절히 분기하여 안내해주어야 했으나, 리눅스 스크립트의 조치 라인을 안일하게 복사-붙여넣기하여 포팅한 흔적이 보입니다.

---

## 3. 권장 조치 및 요약

`issue-20` 커밋을 통해 preflight 검증을 강화하는 `autoqafix-doctor` 도구가 신규 도입되었으나, 위 감사 내용과 같이 **중복 호출에 의한 비효율**, **Windows 런처 구성 대비 파이썬 스크립트 내부의 크로스 플랫폼 처리 누락**, 그리고 **핵심 락 검증 로직의 불일치** 등의 품질 결함들이 확인됩니다.

추후 리팩토링 및 수정 시, 특히 `check_lock` 함수에 시간 초과 기반 `is_stale` 판정 추가와 `run_pings`에서의 OS 환경 분기 처리, 중복 실행되는 `usage` 캐싱 구조 설계를 최우선으로 반영해야 할 것입니다.
