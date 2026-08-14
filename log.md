# KIRA 하네스 분석 로그

## 2026-08-15 — hard 태스크 8건 실패 트라젝토리 분석

대상: `data/failed_trajectories/*.md` (job 2026-08-14__22-27-06, retry). 상세 원문: `data/fail_report.md`.

### 결론

8건 중 5건이 에이전트가 아니라 **하네스 버그가 지배적 원인**. 나머지 3건은 에이전트 실수, 1건은 벤치마크 자체 결함 동반.

티켓: KIRA-2~8 (Yesod). 착수 순서 권장 — KIRA-3 → 4 → 2 → 6 → 7 → 5 → 8. 앞의 셋만으로 타임아웃 6건 중 5건 회수 예상.

| 태스크 | 귀책 | 한 줄 원인 |
|---|---|---|
| feal-differential-cryptanalysis | 하네스 | 79스텝 전부 빈 keystrokes 전송, 터미널 상호작용 0 |
| fix-code-vulnerability | 하네스 | 240스텝 중 229스텝 빈 응답 루프 → 1800s 타임아웃 |
| model-extraction-relu-logits | 하네스 | 136스텝 중 129스텝 빈 응답 루프 → 타임아웃 |
| make-doom-for-mips | 하네스 | 8KB 파일 타이핑 무성 절단, 재시도 40스텝 → 타임아웃 |
| torch-pipeline-parallelism | 하네스 | 좀비 프로세스가 tty 점유, stale 화면 42스텝 무한 반환 |
| configure-git-webserver | 에이전트 | sshd/`user` 계정 미설치 (검증 경로 미확인) |
| protein-assembly | 에이전트 | FASTA의 `X`(발색단 3잔기)를 Ala 1개로 오역, 정답 보고도 폐기 |
| sam-cell-seg | 에이전트+벤치마크 | overlap 신호 무시 / tuple-list 테스트가 원본 입력 CSV와 모순 |

### 하네스 버그 목록 (증거 확정)

**H1. marker echo 개행 없이 이어붙임** — `terminus_kira/terminus_kira.py:257-268`
keystrokes가 `\n`으로 끝나는지 검사 없이 `echo '<marker>'`를 send → `/appecho`, `'5echo'` 등 명령 오염. 마커가 독립 라인으로 안 찍혀 폴링 조기 종료도 실패 → 매 스텝 duration 만료까지 대기.

**H2. 빈 응답 자기 조건화 루프** — `terminus_kira.py:697-702`
모델이 완전 빈 응답(content "", tool_calls []) 반환 시(디스크 확정: `jobs/.../model-extraction*/agent/episode-*/response.txt`) 빈 assistant 메시지를 히스토리에 그대로 append → 빈 응답 선례가 쌓여 탈출 불가. 서킷 브레이커 없음(`:403`, `:885`). 30KB 출력 절단 직후 시작되는 상관관계 있음(추정). `finish_reason`은 `length`만 검사(`:648`), 로깅 없음.

**H3. 대용량 텍스트 무성 절단**
파일 쓰기 채널이 tmux send-keys(키보드 타이핑)뿐. 터미널 입력 버퍼(약 4KB) 초과분은 커널이 조용히 폐기 — backpressure 없음, 에러/exit code 정상. 실측: 5.4KB base64 전송 → 디스크 1,842바이트. "산출물 파일 자체가 없는" 실패 4건(doom, torch-pipeline, fix-code, model-extraction)의 공통 뿌리.

**H4. 죽은/블로킹된 pane 미감지**
tty 점유 상태에서 어떤 입력에도 같은 캡처 버퍼를 "New Terminal Output"으로 반복 반환(torch-pipeline 스텝 124~165). pane 복구 API 없음.

**H6. keystrokes 키 불일치 무성 처리 (feal 근본 원인, KIRA-6)** — `terminus_kira.py:429`
모델이 키 이름을 `"\"keystrokes\""`(따옴표 포함)로 잘못 생성 → `cmd.get("keystrokes", "")`가 경고 없이 빈 명령으로 처리. 모델은 명령을 보냈다고 믿고 "터미널 고장"으로 오판 → 디버깅 스파이럴 → 제어문자로 파서 붕괴. 스모킹건: `jobs/2026-08-14__20-04-32/feal-*__miMKZuz/agent/episode-5/response.txt`. 원조 Terminus 2 파서에 있던 필수 필드 검증이 KIRA 전환 때 유실됨.

**H5. 기타**
- `task_complete` 체크리스트가 빈 `{}` 재호출로 통과되는 no-op 게이트
- `C-c` 등 제어키가 리터럴 문자열로 타이핑됨
- capture-pane 레이스로 이전 화면 잔재 혼입 (`3__`, `160__` 마커 누출)
- 대화형 bash 히스토리 확장(`!ptr` → `event not found`)이 코드 오염
- tmux 소켓이 `/tmp`에 있어 에이전트의 `rm -rf /tmp/*`에 자기 터미널 파괴됨 (sam-cell-seg)
- 에이전트가 보낸 `\n`이 리터럴 `n`으로 전달되는 이스케이프 불일치 (`/appnecho`)

### 수정 우선순위

1. **H2 (KIRA-3)**: 빈 응답은 히스토리 미기록 + 즉시 재시도(3회). `finish_reason` 로깅 추가. 타임아웃 3건 중 2건 예방
2. **H3 (KIRA-4)**: 512B 청크 분할 paced typing, 부족하면 `tmux load-buffer` 통짜 주입 — "파일 없음" 실패 4건 해결
3. **H1 (KIRA-2)**: `_execute_commands`에서 keystrokes가 개행으로 끝날 때만 marker 전송 — 명령 오염+폴링 실패 동시 해결
4. **H6 (KIRA-6)**: keystrokes 필수 필드 검증 복원 (원조 파서에 있던 것)
5. **폴링 구조 (KIRA-7)**: duration 상한 상향 또는 백그라운드 실행+마커 감지
6. **H4/H5 (KIRA-5)**: pane 무변화 N회 시 에러 반환, 체크리스트 게이트 실효화, tmux 소켓 `/tmp` 밖으로
7. **프롬프트 (KIRA-8)**: 자기 검증 예외 금지, 완료 전 태스크문 재현 검증

### H2 최소 수정안 (확정)

태스크 지식·휴리스틱 0. `_handle_llm_interaction` 691행 부근:

```python
for _ in range(3):
    tool_response = await self._call_llm_with_tools(messages)
    if tool_response.content or tool_response.tool_calls:
        break
    self.logger.warning("empty LLM response, retrying")
```

+ 697~702행 히스토리 append를 `if tool_response.content or tool_response.tool_calls:` 로 가드.

근거: 루프의 동력은 "빈 응답이 히스토리에 쌓여 다음 빈 응답을 부르는" 자기 조건화. 기록하지 않으면 N번째 호출이 첫 호출과 동일 조건이 되어 연속 실패가 확률적으로 독립 → 129회 연속 사고 성립 불가. 3회 모두 비면 기존 경로(경고 피드백 후 다음 에피소드)로 진행, 별도 fail-fast 없음.

### 시간 소모 실체

30분~1시간 런의 대부분은 작업이 아니라 공회전. 타임아웃 6건이 세 갈래로 수렴:
- **빈 응답 루프** (KIRA-3): fix-code 229/240스텝, model-extraction 129/136스텝
- **파일 쓰기 절단 재시도** (KIRA-4): make-doom 40스텝, make-mips
- **폴링 대기 소진** (KIRA-7): train-fasttext 1h 6m, mcmc 38m, extract-moves 31m, sam-cell-seg 103/137스텝, torch-pipeline pip 85스텝

### 참고: 전체 잡 결과 (2026-08-14__20-04-32, 30태스크)

17/30 해결. 실패 13건 = 분석한 hard 8건 + make-mips(KIRA-4), train-fasttext/mcmc(KIRA-7), extract-moves(태스크 자체가 무거움, image_read 112회), video-processing(에이전트 실수, 미분석).
