# CURRENT — ChatGPT Window Title Helper macOS

## 139차 — 2026-11-02 01:21–01:33 KST

**상태:** Header 우측 AX 버튼 순서·활성 상태 진단 코드 수정, 411 assertions PASS, ARM64 최적화 빌드 PASS, TheCompany 서명·설치 PASS, 실제 signed Helper AX 검사 PASS. **전체 Restore All E2E 미완료.**

**GitHub:** canonical `harshlad79/chatgpt-window-title-helper`, branch `feat/macos-adaptive-title-helper`. 소스 최초 `60521530`은 Swift scope 컴파일 실패로 설치 금지; 수정·검증·설치 source `cd7f32a24e15d659db805f498ecfd482fdf5435d`. 상세 작업 원장 `macos/HEADER_MORE_RIGHT_ORDER_20261102.md`, 문서 커밋 `fd7e71fa`. PR #3 Open/Draft, base master, 미병합. Windows 코드/NativeTitleSync 무변경. 원격 6브랜치 전수+master 비교: 미병합 작업 브랜치 1개(`feat/macos-adaptive-title-helper`); app-icon PR #4는 merged, 나머지 2개 기능 브랜치는 master behind, dev는 장기 base.

**MacMini2:** ChatGPT PID 10411 유지, Helper PID 7951, on-screen CG layer0 window IDs 15360/16252 두 표본 안정, session SHA256 `f4fe834b324534ca80e6139ab43a52bccc3bf968babd998c9f19e9580726d104` 불변/mode0600, 서명 PASS. 실제 AX `visited125/buttons47/top12/right2`: 왼쪽 우측 후보 `outer20,next10,enabled=true`, 오른쪽 `edge10,next10,enabled=false`. 둘 다 AXShowMenu/AXPress, AXTitle 있음, AXDescription 없음, parent AXGroup. 정확한 More 라벨 0, 대화 URL/ID 0. 메뉴 클릭/복원 실행 없음.

**실패·복구:** Dev 호출 `tool`→`operation` schema 오류(Worker 미실행), 특정 window `screencapture -l` 내부 exit1(스크린샷 미확보), Swift `top/height` scope 컴파일 exit1→`rootTop/rootHeight` 수정 후 411 PASS, Mac Worker `/usr/bin/kill` exit1→Bash 내장 `kill`로 수정 후 Helper 재시작 성공. OpenAI 사전 안전검사 차단 0, Dev Control 거절 0. Experience `7a792a26-6caa-4cfb-85f5-4c15089bd66f` captured 및 list 재조회 검증. 모든 호출 request/PID/elapsed/route는 상세 원장 참조. Terminal 전면 스크린샷은 ChatGPT UI 증거 아님. TCC 우회/권한 변경 없음.

**롤백:** 기존 설치 앱 백업 `[비공개]/titlehelper-139-right-order-60521530/artifacts/macos/backups/titleoverlay-before-event.xf0Isd7U/ChatGPTTitleOverlay.app`; 설치·서명·원본 세션 검증 PASS이므로 롤백 불필요.

**다음:** 기존 Header More 정확한 AX 부모/제목 버튼 연결 확인. 식별 전 클릭 금지. URL/ID 획득→개별 native 창 복원→전체 Restore All E2E 순서. 기존 창 종료·덮어쓰기 금지. 예약 유지.

**알림:** 오류 회차이므로 Telegram 우선/Windows 별도 독립 보고. 접수 영수증은 본 파일의 139차 후속에 기록하며, 기기 화면 표시와 구분.

---

**138차 알림 접수 후속 — 2026-11-02 00:29~00:30 KST:** 초기 호출자 패치 문자열 매칭 오류(전송 전 실패, 후속 수정·실제 Mac 검증 완료)가 있어 사용자 조건부 정책대로 **Telegram 우선 → Windows 별도** 독립 제목/본문 생성. 공통 1~6항 순서, 실제 LF(U+000A), 리터럴 백슬래시+n 없음. 제목 `[ChatGPT Window Title Helper] · [macos-main]`, body 첫 줄 `[실제 대화 제목 미확인] ChatGPT Window Title Helper macOS — 마지막 창 모두 복원`. Telegram 본문 **1282자**(상세), Windows **723자**(<1000), 개인정보·인증정보·원시 대화 미포함.

1. **Telegram:** Dev Control-only `thecompany_call_tool(operation=enqueue_notification)`, request `8510fe47-4d74-4b3c-91c2-2f1a7f9aad06`, `notification_destination=telegram`, `source_node=macos-main`, `project=chatgpt-window-title-helper`, `session_ref=6ad8d8ff97ac8191b351582129a28330`, `task_label=마지막 창 모두 복원 138차`; notification `d3e20506-bdc3-4d0c-84f1-f0eccd487b19`, outer/nested completed/queued elapsed3ms. `get_notification` request `93656c91-f231-4c53-a813-f9e03c8d4565`, outer/nested completed elapsed1ms, **registered attempt1 accepted=true exit0 message_id218**. Provider PID 미제공.
2. **Windows(windows-main):** 별도 723자 body. `enqueue_notification` request `bbbbb909-9259-47bb-babb-b4c1543416f9`, notification `cb5311a4-8a89-47d8-9840-946465962ebb`, outer/nested completed/queued elapsed4ms. `get_notification` request `816b241e-52f2-4332-944e-95140261656f`, outer/nested completed elapsed1ms, **registered attempt1**, Windows NodeAgent `pythonw.exe(pid=11848)` → `python:subprocess/run_command` → `powershell.exe(pid=24848)`, cwd `D:\\_Project\\thecompany-core`, exit0/timed_out=false/HTTP200, `WINDOWS_NOTIFICATION_REGISTERED`.
3. **결과:** 두 채널 큐 접수·목적지 등록 확인, 실패·재시도 없음. 실제 기기 화면 표시·사용자 열람 **미검증**. Control-only `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=850940) -> control.enqueue_notification/get_notification`, `mcp_trace` Control PID850940, Mac Worker 없음. 본 후속은 문서 전용; 검증·설치 source `3ecf9ad3` 유지, 전체 Restore All E2E 미완료, 예약 유지.
