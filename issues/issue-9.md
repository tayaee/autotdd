# issue-9: 공용 코어 — preflight와 뮤텍스

## 배경

모든 진입점이 공유하는 안전장치. `.claude/skills/autoqafix/autoqafix_core.py` 모듈로 만들고
이후 이슈들의 스크립트가 import한다(같은 디렉토리이므로 sys.path 조작 없이 가능).

## 요구사항

1. `.claude/skills/autoqafix/autoqafix_core.py` 작성. 함수:
   - `preflight(role: str, repo: Path) -> list[str]`: 실패 항목들의 메시지 목록
     반환(비면 통과). 각 메시지는 정확히 두 줄 `[원인] ...\n[조치] ...`.
     검사 항목: ① cwd가 git repo 루트(`git rev-parse --show-toplevel` == cwd),
     ② `issues/` 존재, ③ role이 qa면 `logs/` 존재, ④ `uv` PATH 존재,
     ⑤ `git config user.name`/`user.email` 설정됨, ⑥ `git ls-remote origin`
     30초 내 성공, ⑦ role이 fix/dev면 `~/.claude/skills/{autotdd,tdd2,acpd}` 존재
   - `acquire_lock(role, repo) -> bool` / `release_lock(repo)`:
     `<repo>/.git/autoqafix.lock`에 `host=`,`pid=`,`role=`,`start=`(ISO8601) 기록.
     잠금 존재 시: 같은 호스트면 PID 생존 확인, 죽었으면 회수; 시작 후
     14400초(4시간, env `AUTOQAFIX_LOCK_STALE_SEC`) 초과면 부실로 회수;
     아니면 False 반환(호출측이 "이미 <role>이 실행 중 (<host>, <start>)" 출력)
   - `clone_id(repo) -> str`: sha1(절대경로 문자열) hex 앞 12자
   - `state_dir(repo) -> Path`: `~/.cache/autoqafix/<clone_id>/` (없으면 생성)
   - `run_with_timeout(cmd, timeout_sec) -> (exit, stdout, stderr, timed_out)`:
     타임아웃 시 프로세스 그룹 전체 kill (Windows 호환: `subprocess` +
     `taskkill /T` 분기 주석으로 명시)
2. 모듈 자체도 PEP-723 헤더 포함, `uv -q run autoqafix_core.py --selftest`로
   위 함수들의 단위 자체시험 실행 가능

## 승인 기준

- [ ] 픽스처 repo에서 preflight("qa") 통과(빈 목록), `logs/` 삭제 후 `[원인]` 포함
      1건 반환
- [ ] git repo 아닌 디렉토리에서 ① 위반 메시지 반환
- [ ] 잠금: 1차 acquire True → 2차(다른 role) False → release 후 True.
      start를 5시간 전으로 조작한 잠금은 회수된다
- [ ] `run_with_timeout(["sleep","10"], 1)`이 1초 부근에 timed_out=True
- [ ] `--selftest`가 exit 0

## 검증

`regression-tests/verify-issue-9.sh` 작성: `--selftest` 실행 + 픽스처 repo에서의
preflight/lock 시나리오.
