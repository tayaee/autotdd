# issue-13: error-to-autofix — 보고 파이프라인 조립
agent-tier: paid-only

## 배경

qa 롤의 완성: 스캔 → dedup → top5 → LLM 작성 → 번호 예약 → push.
명세: `docs/autoqafix-design.md`의 "autoqa" 전체.

## 요구사항

1. `.claude/skills/autoqafix/error-to-autofix.py` 작성 (PEP-723). CLI:
   `uv -q run .claude/skills/autoqafix/error-to-autofix.py --repo <path>`
2. 절차:
   ① select-llm 호출(issue-9) — 결과가 로컬 래퍼나 `none`이면 "유료 LLM 부적격,
   보고 연기" 출력 후 exit 0 (**오프셋 비전진**: log-scan을 --dry-run으로만 사용)
   ② log-scan 실행(JSON 수신)
   ③ dedup: `issues/`의 미결 항목(`issue-*`/`autofix-*` 모든 접미사 포함,
   archive 제외)에서 `dedup-key: <key>` 문자열 검색, 있으면 제외
   ④ 남은 것 중 count 상위 5개만
   ⑤ 각 항목: 선정 래퍼를 `-p <프롬프트>`로 호출(경량 타임아웃
   AUTOQAFIX_LIGHT_TIMEOUT, 기본 1200초). 프롬프트에 포함: excerpt, count, 지시
   "배경/요구사항/승인 기준 3섹션 형식의 한국어 issue 본문과 첫 줄 제목,
   그리고 agent-tier(local-ok|paid-only|manual) 판정을 출력하라. 마지막 줄은
   `TIER: <값>`" — 출력 파싱: 마지막 `TIER:` 줄에서 tier, 첫 줄에서 제목
   ⑥ reserve_number → finalize_item(issue-11). 본문에 반드시 포함:
   `dedup-key:` 줄, `agent-tier:` 줄, `frequency: <count> (<window>)` 줄,
   발췌 코드블록, 지시문 "로그 원문(logs/)을 열지 말 것 — 필요한 발췌는 이 문서에
   포함됨"
   ⑦ tier가 `manual`이면 finalize 직후 `-manual`로 `git mv` + commit + push
   ⑧ 5개 전부 성공 후에만 log-scan을 실제 모드로 재실행해 오프셋 전진.
   래퍼 호출 실패/타임아웃 시 해당 항목 건너뛰고 오프셋 비전진(다음 사이클 재시도)
3. 모든 git 조작은 `--repo`가 가리키는 트리 안에서만

## 승인 기준

픽스처 + fake-wrapper(FAKE_OUTPUT_FILE로 준비된 본문·TIER 응답) 사용:

- [ ] AUTOQAFIX_WRAPPER=<fake, claudecli 역>으로 실행 → 원격에 `autofix-1.md` 생성,
      본문에 dedup-key/agent-tier/frequency/발췌/지시문 5요소가 모두 있다
- [ ] 즉시 재실행 → dedup에 걸려 새 항목이 생기지 않는다
- [ ] TIER: manual 응답 픽스처 → `autofix-N-manual.md`로 원격에 존재
- [ ] AUTOQAFIX_WRAPPER 미설정 + select-llm이 none인 픽스처 → "보고 연기" 출력,
      offsets.json 파일이 갱신되지 않았다 (mtime/내용 비교)
- [ ] 에러 7종을 심으면 top5만 보고된다

## 검증

`regression-tests/verify-issue-13.sh` 작성: 위 전부. 실 LLM 호출 금지.
