# issue-17: autofix/autodev 런처 6종
agent-tier: local-ok

## 배경

fix/dev 롤의 repo 루트 진입점. issue-14의 autoqa 런처와 동일 패턴이다.
autodev = 같은 엔진, `--stream issue` 고정.

## 요구사항

1. repo 루트에 `autofix.{sh,ps1,bat}`, `autodev.{sh,ps1,bat}` 작성 — issue-14
   런처 패턴 그대로: 자신의 위치(`$0`/`%~dp0`) 기준으로
   `.claude/skills/autoqafix/autofix.py`를 찾아 `uv -q run <절대경로> --repo
   <현재 cwd>`로 실행, `uv` 부재 시 `[원인]`/`[조치]` 출력 후 exit 127,
   `.bat`은 비정상 종료 시 `pause`
2. `autodev.*`는 `--stream issue`를 추가로 전달한다

## 승인 기준

- [ ] 픽스처 repo를 cwd로 `autofix.sh` 실행(AUTOQAFIX_WRAPPER=fake,
      FAKE_MODE=archive) → issue-16과 동일 결과(`FIXED=1`)
- [ ] `autodev.sh`는 issue 스트림 항목만 처리한다 (픽스처에 issue-1.md와
      autofix-1.md를 두면 issue-1.md만 archive됨)
- [ ] `.sh` 2종 `bash -n` 통과, `.bat` 2종에 `pause` 존재(grep)

## 검증

`regression-tests/verify-issue-17.sh` 작성: 위 전부 자동화.
