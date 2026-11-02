# 101차 — 2026-10-31 05:27–05:34 KST — ChatGPT 대화 URL 식별자 파서 안전성 회귀 강화

## 1. 제목·일시
ChatGPT Window Title Helper macOS — 마지막 창 모두 복원. 101차, 2026-10-31 05:27–05:34 KST (Mac 실측 05:33:48+0900).

## 2. 전체 상태
**정확한 GitHub 소스에서 합성 대화 URL 파서 회귀 17개 추가, MacMini2 전체 Swift 테스트/ARM64 빌드 PASS. 실제 고유 URL 확보·별도 네이티브 창·전체 Quit→relaunch→Restore All E2E는 미완료.** 이번 회차는 테스트만 변경. 설치 Helper는 교체하지 않음.

## 3. 수행·근거
- canonical GitHub `harshlad79/chatgpt-window-title-helper`, branch `feat/macos-adaptive-title-helper`, 시작 HEAD `da5f06655c4d7fc8adfc8166514be6cc79a1607b`. PR #3 **Open/Draft**, base `master`, unmerged. 필수 `docs/continuity/CURRENT.md`, `macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md`, `macos/DOCK_LAST_SESSION_BULK_RESTORE.md` 원문 및 공유 Rulebook 원문 조회. 원격 브랜치 6개, cursor `Ng` 후 0개로 전수 종료. master/dev 장기 기반 제외: 작업 브랜치 master 대비 ahead374/behind1; app-icon ahead1/behind1이지만 PR #4 merged; title-change-event-probe ahead0/behind2; fix/chatgpt-2026-title-ui ahead0/behind7. **검증된 미병합 기능 브랜치 1개**.
- 기존 `ConversationRouteIdentity.parse`는 URL을 직접 탐색/복원하지 않는 연구단계 파서. 합성 UUID만으로 정확한 `https://chatgpt.com/c/<UUID>`, `/g/<slug>/c/<UUID>`의 round-trip, www canonicalization, HTTP/host-suffix spoof/userinfo/port/fragment/trailing slash/percent-encoded project path/path traversal/invalid slug/query/non-UUID 거절을 검증하는 **17 assertions** 추가. URL이나 실제 사용자 대화 ID는 수집/로그하지 않음.
- 최초 테스트 파일 커밋 `3591ed34fc1120cdbb913520a7b44edc3fd5a41d`의 신규 합성 URL 일부에서 Swift 문자열 interpolation backslash가 이중 이스케이프됨. **Mac 테스트 실행 전** 해당 11개 문자열을 올바른 interpolation으로 수정한 커밋 **`9c19a4f9aa05b58e506e2ba6a4b5484d89d0ce67`** 생성. 이 정확한 SHA만 Mac에서 테스트함.
- Mac 격리 worktree `~/_Project/titlehelper-101-9c19a4f9`, exact SHA `9c19a4f9`, source clean. `bash macos/tests/run.sh` 최종 **exit0**, NativeTitleSync byte identity PASS, scheduler14, history/session59, native batch91, asynchronous restore100, focused-menu URL **46 assertions PASS (이전29+17)**, 합계 310 assertions. `LIVE_AX_MENU_URL=NOT_TESTED`. ARM64 optimized `BUILT artifacts/macos/ChatGPTTitleHelper`, SHA256 `0429e11e0ad0455f2acaec987a63b9ff1e4488e0f29ebb50d1ab62ffb6b4086a` (이전 빌드와 동일: 테스트 전용 변경). 바이너리 **미설치/미실행**.
- Mac 실제 런타임 읽기 전용: ChatGPT PID **27828**, 기존 Helper PID **15201**, 설치 서명 PASS. full history SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159` 불변; partial SHA256 `56e9cf97ce9930867e396d03a0f46cb5c284162f23c2f298a4910ce078b7a418` 불변. 현재 partial `appPID27828/raw8/entries5/minimized2`; 완전 인식은 이전 AX 로그에서 3개. 공식 메뉴 `ax-focused-menu-sampler` 최근 heartbeat `foreground=false trusted=true targetValid=true inFlight=false`, URL 후보 이벤트 0. **메뉴 미개방 상태이므로 URL 부재 증거가 아님**. Dev 화면 캡처는 Terminal 전면을 확인했으며 클릭/입력 없음. 개인 화면 픽셀 GitHub 비첨부.
- 기존 연구의 중요한 한계 유지: native `open-in-new-window` 내부 route guard는 일반 `/c/<UUID>`를 거절(83차 정적 조사), OS HTTPS open-url은 기존 브라우저 패널로 향할 수 있음(84차 정적 조사). 따라서 파서 PASS는 **새 네이티브 창 복원 성공이 아님**.

## 도구 호출·실행 경로
1. GitHub connector `fetch_file`(필수3/Rulebook/Swift/테스트/연구), `get_pr_info`(#3/#4), `search_branches`(6+0), `compare_commits`(4), `update_file`(테스트 2커밋), `create_file`(본 원장), `update_file`(CURRENT 예정). GitHub는 Control/Worker 미경유; request_id/mcp_path/PID/elapsed/exit_code 미제공. `macos/tests/verify_focused_menu_url_probe.swift`라는 추정 경로 `fetch_file` 404 발생. 실제 `macos/tests/menu_probe/main.swift`를 `macos/tests/run.sh`에서 확인해 수정; 404는 **GitHub 경로 추정 오류**, Mac Worker/Dev Control/사전 안전검사 실패 아님.
2. Dev `thecompany_status` 및 `thecompany_describe_control_operation(invoke/get_latest_success/enqueue_notification/get_notification)` 메타데이터 조회. `thecompany_call_tool` 최초 인자에 `tool`을 사용해 **functions.exec 입력 스키마 사전 거절**(`operation` 필수), request_id/mcp_path/mcp_elapsed_ms/exit_code **미발급**. 정확한 `operation`으로 재호출 성공. 이는 OpenAI 사전 안전검사 차단이 아니라 **커넥터 인자 검증 오류**이며 Dev Control이나 Mac Worker에 요청 도달하지 않음.
3. Dev `thecompany_call_tool(operation=get_latest_success)` request `7be3e1d3-c35c-4f81-9a53-1e32f35d5f59`, outer/nested completed, 2ms, `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=772807) -> control.get_latest_success`; 100차 성공 영수증 확인.
4. Dev `thecompany_capture_screen(max_width=1100)` 이미지 수신: Terminal 전면. request_id/mcp_path/PID/elapsed 미제공. UI 조작 없음.
5. Dev `thecompany_call_tool(operation=invoke)`, 공통 `node_id=macos-main,project=chatgpt-window-title-helper,backend=python:subprocess,worker_tool=run_command`, `program=/bin/bash`, `args=[-lc,<읽기전용 상태·격리 SHA fetch/worktree·background run.sh 시작·진행/완료/해시 확인>]`, timeout15–28s, read-only에 `procedure_key=macos-title-helper-live-readonly`, cwd=[비공개]. 공통 실제 `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=772807) -> control.invoke -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<아래>)`; `mcp_trace` 동일. 모든 요청 **outer/nested completed, Worker exit0, timed_out=false**, task_id 미발급:
   - `d58215b5` bash88007/1013ms: PID/서명/세션 SHA/AX·URL 로그 읽기.
   - `4ce3c81b` bash90208/3560ms: SHA `9c19a4f9` clean worktree, background `run.sh` PID90270 시작.
   - `094afd5a` bash90316/254ms: NativeTitleSync PASS, 진행 확인.
   - `3fa09a1d` bash90390/18524ms: scheduler14/history59/batch91/async100/menu46 PASS, 빌드 진행.
   - `71dbcac9` bash91223/20492ms: 빌드 진행.
   - `be668acc` bash91485/20396ms: 빌드 진행.
   - `2e6cc60f` bash92383/393ms: swift-frontend CPU 진행 확인.
   - `f170c558` bash92463/18366ms: 빌드 진행.
   - `b85d5dac` bash92639/18484ms: 빌드 진행.
   - `0c2dd797` bash93526/14314ms: **run.sh exit0 / BUILT** 확인.
   - `97155f0a` bash93664/1016ms: exact SHA/clean/빌드 해시/원본 PID/서명/세션 두 SHA/partial raw8 entries5 재검증.
   - `515053a4` date94277/135ms: 2026-10-31T05:33:48+0900 확인.
6. 알림 Control-only `enqueue_notification/get_notification`은 후속 CURRENT 영수증에 별도 기재. **OpenAI 사전 안전검사 차단 0, Dev Control 거절 0, Mac Worker 실패 0**. 커넥터 스키마 사전 거절 1, GitHub 추정 경로 404 1, 테스트 fixture 수정 1은 위와 같이 별도 분류. `type=tool_boundary` 사전 안전검사 차단 조건 미발생. 운영 MCP/Work/Codex/TCC 우회/코드 인젝션 없음.

## 4. 최종 상태·기존 영향
테스트 전용 두 커밋만 feature branch에 반영. 설치 Helper **15201**/ChatGPT **27828** 유지. 기존 8개 AX 창의 partial metadata 5건과 세션 SHA 불변. 실제 복원 버튼/새 창/검색/메뉴/클립보드/공유 링크를 조작하지 않음. Windows 소스, NativeTitleSync, Draft PR #3 변경 없음. 롤백 불필요.

## 5. 미완료·다음
**우선순위는 더 많은 합성 테스트가 아니라 실제 비민감 대화의 공식 메뉴에서 URL/ID가 AX로 노출되는지 확인하는 것.** ChatGPT가 자연스럽게 전면에 있고 메뉴가 열린 안전한 시점에 설치된 동일 프로세스 350ms passive sampler의 `routeCandidates/conversationURLs`를 읽는다. URL이 나타나도 현재 AXWindow와 동일 대화인지 별도 검증 필요. 메뉴가 계속 닫혀 있으면 비민감 격리 Search UI의 지원된 새 창 액션을 검토하되 owner 창 탐색/덮어쓰기/강제 Quit 금지. 네이티브 새 창/제목·본문/전체 Restore All E2E **미완료**.

## 6. 사용자 조치·알림
현재 사용자 조치 없음. 다만 이번 회차 커넥터 인자/경로 오류를 수정했으므로 정책에 따라 **Telegram 우선 → Windows 후속** 알림을 보내고 각각 `get_notification`으로 등록 여부 확인. 등록 성공과 실제 화면 표시 구분. 실제 알림 영수증은 CURRENT.md 후속 기록.
