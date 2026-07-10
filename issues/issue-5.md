# issue-5: qwencli 래퍼 3종

## 배경

로컬 무료 LLM용 래퍼. 내부에서 `qwen`(qwen.exe)을 호출하므로 자기호출 충돌을 피해
이름은 `qwencli`다(`qwen.{bat,ps1,sh}` 금지 — CONTEXT.md "LLM 래퍼" 참조).

## 요구사항

1. `.claude/skills/autoqafix/wrappers/`에 `qwencli.sh`, `qwencli.ps1`,
   `qwencli.bat` 작성
2. 동작: 받은 인자를 그대로 `qwen`에 전달 (`qwen -p PROMPT` 형태 지원).
   `qwen`은 PATH에서 찾는다(하드코딩 금지)
3. claudecli/minimaxcli와 동일한 인자 규약: 첫 인자가 존재하는 파일이면 내용을 stdin으로
   `qwen -p`에 파이프
4. `qwen`이 PATH에 없으면 `[원인] qwen CLI가 PATH에 없음` + `[조치] qwen 설치 또는
   PATH 추가` 출력 후 exit 127

## 승인 기준

- [ ] PATH 앞에 `fake-qwen.sh`를 `qwen`으로 심고 `wrappers/qwencli.sh -p "hi"` →
      `FAKE_LOG`에 `-p hi`가 기록되고 exit 0
- [ ] `qwen`이 PATH에 없는 환경에서 exit 127 + `[원인]`/`[조치]` 두 줄 출력
- [ ] `bash -n qwencli.sh` 통과, `.bat`/`.ps1`은 존재 + `qwen` 호출 grep 확인

## 검증

`regression-tests/verify-issue-5.sh` 작성: 승인 기준 자동화 (fake-qwen 사용).
