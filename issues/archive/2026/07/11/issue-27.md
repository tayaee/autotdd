# issue-27: Windows 런처의 uv 설치 안내 교정 (.bat/.ps1 전체)
agent-tier: local-ok

## 배경

issue-20 리뷰 종합 판정(`issue-20-feedback-review-by-fable.md` M6,
원 지적: gemini ⑥). 모든 `.bat`/`.ps1` 런처가 uv 부재 시 조치로 Linux
셸 전용 `curl -LsSf https://astral.sh/uv/install.sh | sh`를 안내한다.
Windows CMD/PowerShell에서 그대로 실행하면 실패하는 잘못된 안내.
issue-20의 doctor 런처가 기존 런처 패밀리에서 물려받은 패턴이므로
시정 범위는 repo 루트의 `.bat`/`.ps1` 전체(현재 7종 × 2 = 14파일 +
`deploy.bat`/`deploy.ps1`에 같은 라인이 있으면 포함).

## 요구사항

1. `.ps1` 런처의 조치 라인을
   `irm https://astral.sh/uv/install.ps1 | iex`로 교체
2. `.bat` 런처의 조치 라인을
   `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`로 교체
3. `.sh` 런처는 기존 `curl ... | sh` 유지 (플랫폼 정합)
4. 런처 패밀리의 다른 관례(pause 유무, exit code 전파, `[원인]`/`[조치]`
   2줄 포맷)는 변경하지 않는다

## 승인 기준

- [ ] repo 루트 `.bat`/`.ps1` 파일에서 `install.sh | sh` 안내 0건
- [ ] 모든 `.bat`/`.ps1`에 `install.ps1`(irm/iex) 안내 존재
- [ ] `.sh` 런처는 변경 없음
- [ ] 기존 회귀 전체 PASS (런처 grep 검사 포함)

## 검증

`regression-tests/verify-issue-27.sh` 작성: grep 기반 — ① `.bat`/`.ps1`
전수에서 `install.sh`(sh 파이프) 부재, ② `install.ps1` 존재, ③ `.sh`
런처의 기존 안내 유지, ④ `bash -n`/pause 등 기존 정적 검사 회귀 없음.

## 구현 결과

- **구현 완료 일시**: 2026-07-11T12:58:00-04:00
- **변경 파일**:
  `autoqa.bat`, `autoqa.ps1`, `autoqa-loop.bat`, `autoqa-loop.ps1`,
  `autofix.bat`, `autofix.ps1`, `autofix-loop.bat`, `autofix-loop.ps1`,
  `autodev.bat`, `autodev.ps1`, `autodev-loop.bat`, `autodev-loop.ps1`,
  `autoqafix-doctor.bat`, `autoqafix-doctor.ps1`,
  `regression-tests/verify-issue-27.sh`
- **계획과 차이**: 없음. deploy.bat/deploy.ps1은 uv 안내 자체가 없는
  deploy 책임 스크립트라 시정 범위에서 제외(grep 검사에서도 별도 단언).
- **검증 결과**: verify-issue-27.sh ALL PASS (36 PASS, 0 FAIL).
  전체 회귀 테스트 21/21 PASS.
