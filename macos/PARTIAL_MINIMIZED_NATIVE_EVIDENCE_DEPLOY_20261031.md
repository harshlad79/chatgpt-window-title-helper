# 100차 — 2026-10-31 04:21–04:24 KST — 최소화 창 부분 증거 기능 실기기 배포 및 3→5 검증

## 1. 제목·일시
ChatGPT Window Title Helper macOS / 마지막 창 모두 복원 / 100차 / 2026-10-31 04:21–04:24 KST.

## 2. 전체 상태
**99차 소스 `a29a9e2dd653edc627826a572b55ba08bae72b2f`의 최소화 창 native AX 제목 보조 수집 기능을 MacMini2에 서명·배포. 실제 부분 스냅샷 항목이 3→5개로 증가했고, 최소화 native 제목 보조 증거 2개가 추가된 것을 확인.** 전체 정상 Quit→재실행→Restore All E2E는 **미완료**.

## 3. 수행·검증·근거
- 권위 원천 GitHub `harshlad79/chatgpt-window-title-helper`, 브랜치 `feat/macos-adaptive-title-helper`, 시작 HEAD `8396fcff61bef000047fc55c1edec841676ce6ef`. PR #3 **Open/Draft**, base `master`, 미병합. `docs/continuity/CURRENT.md`, `macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md`, `macos/DOCK_LAST_SESSION_BULK_RESTORE.md`, 공통 Rulebook 원문 조회. GitHub 소스 변경 없음. 이번 회차 문서 커밋만 추가.
- GitHub remote branch search `page_size=100`: 첫 페이지 6개, cursor `Ng` 다음 페이지 0. `master`/장기 `dev` 제외. `feat/macos-adaptive-title-helper` ahead372/behind1; `feat/approved-app-icon-20261016` ahead1/behind1이나 PR #4 **merged**; `feat/title-change-event-probe` ahead0/behind2; `fix/chatgpt-2026-title-ui` ahead0/behind7. **검증된 미병합 기능 브랜치 1개**.
- 정확한 소스 SHA `a29a9e2d`의 clean Mac worktree `~/_Project/titlehelper-99-a29a9e2d` (`git status --porcelain` 0). 99차 이미 수행된 테스트: NativeTitleSync byte identity PASS, Swift scheduler14/history59/batch91/async100/menu29 assertions PASS, ARM64 최적화 빌드 exit0. 이번 회차 **테스트 재실행 없음**; 이전 빌드의 unsigned SHA256 `0429e11e0ad0455f2acaec987a63b9ff1e4488e0f29ebb50d1ab62ffb6b4086a`를 실제 확인.
- 설치된 기존 앱 `~/Applications/ChatGPTTitleOverlay.app` Bundle ID `local.chatgpt.titleoverlay`, 실행파일 `ChatGPTTitleOverlay`, 기존 Authority `TheCompany` 확인. 인증서 이름이 유사한 `TheCompany Local Signing Test 2026`과 혼동하지 않고 **정확한 `TheCompany`**로 후보 앱 서명. strict/deep 검증 PASS. signed candidate SHA256 `15a8f1130b9ec12a1f2af7c8b73b268049410bac9a10a317cb63f86d7acf00da`.
- **배포 전 비파괴 보존:** ChatGPT PID **27828**, Helper PID **79851**, CGWindow **18개**, onscreen **5개**, CG ID 18개 기록. durable session SHA `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159`, partial SHA `ed981c6b1ab2b49e58b79a3f1116d7148983600bb49c2e1eacfdc3b65448154d`, 두 파일 mode0600. 기존 서명 앱·두 세션 파일을 `~/_Project/titlehelper-99-a29a9e2d/artifacts/macos/100-stage/`에 독립 백업. 앱 번들 및 ChatGPT 자체에는 변경 없음.
- **Helper-only 배포:** 기존 Helper PID79851에 SIGTERM, 종료 확인 후 앱만 교체; `/usr/bin/open --env TITLEHELPER_SAFE_FOCUSED_MENU_URL_PROBE=1 --env TITLEHELPER_SAFE_AX_WINDOW_SNAPSHOT=1 -a <Helper.app>`로 LaunchServices 기동. 새 Helper PID **15201**, ChatGPT PID **27828 유지**. 코드서명 PASS, 설치 SHA는 위 후보 SHA와 일치. 실패 시 이전 서명 앱을 복원·LaunchServices 재기동하는 trap 준비, 실제 롤백 불필요.
- **배포 후 실측:** `window-session-partial.json`의 appPID27828/raw8/**entries5**/minimizedEvidence2/indexes `0,1,4,5,6`. 배포 전 entries3 → 배포 후 **5**. `window-session-history.json` SHA **불변**, appPID501/lastComplete3/previous5. 부분 증거는 Restore All 대상/고유 ID/완전한 세션으로 승격되지 않음. AX 로그의 `ax-window-census raw8 recognized3 nativeNamed5 nativeGeneric3 minimized3`은 별도 수치: **완전 인식 3, 부분 관측 5**를 혼동하지 말 것.
- 배포 후 CGWindow **18개**, onscreen **5개**, **CG ID 18/18 보존**, 추가/소실 0. `ax-observer-created=true pid=27828`, `ax-focused-menu-sampler foreground=false trusted=true targetValid=true inFlight=false` 확인. 화면 캡처 2회에서 Terminal 전면, ChatGPT 공식 대화 메뉴 없음. 사용자 창 활성화/닫기/종료, 메시지 입력, TCC 우회, 코드 인젝션 없음.
- **실제 AXURL 후보/고유 대화 ID/독립 새 창/본문 검증 미수행**, 전체 Restore All E2E 미완료. 화면의 메뉴가 열려 있지 않은 사실을 AXURL 부재의 증거로 해석하지 않음. Windows 코드/NativeTitleSync/PR #3 변경 없음.
- **오류 분류:** OpenAI 사전 안전검사 차단 **0**; Dev Control 거절 **0**; Mac Worker 비정상 종료 **0**; 복구/롤백 필요 없음. `type=tool_boundary` 차단 기록 조건 미발생.

## 도구 호출·실행 경로 (시도별)
1. GitHub connector: `fetch_file`(필수 3문서, Rulebook, 소스·테스트·빌드 스크립트·이전 배포 원장), `get_pr_info`(#3/#4), `search_branches`(6+0, cursor 소진), `compare_commits`(master 대비 4개), `create_file`(본 문서), `update_file`(CURRENT). **GitHub는 Control/Worker 미경유**; request_id/mcp_path/PID/elapsed/exit_code 미제공.
2. Dev `thecompany_describe_control_operation(invoke,execute,enqueue_notification,get_notification)`: read-only 계약 조회, Control Worker 미실행, request_id/mcp_path/PID 미제공.
3. Dev `thecompany_capture_screen(node_id=macos-main,mode=desktop,max_width=1100/1000)` 2회: Terminal 전면 스크린샷 확인. 화면 클릭/키입력 없음, request_id/mcp_path/PID/elapsed 미제공. 이미지 자체는 사용자 개인정보 보호를 위해 GitHub에 올리지 않음.
4. Dev `thecompany_call_tool(operation=invoke)` request `f45a1b5d-61cd-41de-a85a-39ad54d16871`, Mac bash PID13857, 1224ms, outer/nested completed, exit0: 기존 ChatGPT/Helper PID·서명·세션 SHA·worktree·부분 관측 수 read-only 확인.
5. Dev `thecompany_call_tool(operation=invoke)` request `99306390-233e-46ee-8f02-51cd7b45288e`, Mac bash PID14012, 662ms, outer/nested completed, exit0: 정확한 source SHA, clean tree, 빌드 SHA, Bundle ID/실행파일/서명 인증서, 로그 확인.
6. Dev `thecompany_call_tool(operation=invoke)` request `42ef09bd-54dc-4266-a580-81d485308fd0`, Mac bash PID14837, 4473ms, outer/nested completed, exit0: 기존 앱·세션 백업, 후보 앱 서명, strict 검증. 배포 전 후보 signed SHA 확인.
7. Dev `thecompany_call_tool(operation=invoke)` request `1de753a1-30d1-4efa-a74c-7b7bc0b1992f`, Mac bash PID14986, 5325ms, outer/nested completed, exit0: Swift Quartz CGWindow read-only 기준선 18개·5 onscreen·18 ID, AX 로그 raw8/recognized3, 부분3 확인.
8. Dev `thecompany_call_tool(operation=invoke)` request `ec5ffdd5-d501-4b22-af43-09db9229de9d`, Mac bash PID15178, 2691ms, outer/nested completed, exit0: Helper-only SIGTERM/교체/LaunchServices 재실행, 실패 시 롤백 trap, 새 PID15201·ChatGPT PID27828·history SHA 보존·서명 검증.
9. Dev `thecompany_call_tool(operation=invoke)` request `edd33899-e211-4f17-9dc4-f3e1322173a1`, Mac bash PID15602, 7685ms, outer/nested completed, exit0: signed SHA, session SHA, partial entries5/minimized2, CG ID18/18, observer/heartbeat 확인.
- 위 6개 Mac 호출 공통 공개 인자: `node_id=macos-main`, `project=chatgpt-window-title-helper`, `backend=python:subprocess`, `worker_tool=run_command`, `tool_arguments={program:/bin/bash,args:[-lc,<각 읽기·백업·서명·배포·검증 스크립트>],timeout_seconds:22–45}`. 읽기 전용 호출에는 `procedure_key=macos-title-helper-live-readonly`. 실제 cwd=[비공개], task_id 미발급. **실제 공통 mcp_path** `control-n150/thecompany-chatgpt-mcp:python(pid=772807) -> control.invoke -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<위 개별 PID>)`; mcp_trace Control PID772807/Mac Agent PID5070/각 bash PID. 모든 Worker `timed_out=false`.

## 4. 최종 상태·기존 영향
배포 소스 `a29a9e2d`, 서명 설치 SHA `15a8f113...`, Helper PID15201, ChatGPT PID27828, CG ID18/18, full session SHA 불변. partial 증거3→5 **실제 검증 성공**. 롤백 백업 `~/_Project/titlehelper-99-a29a9e2d/artifacts/macos/100-stage/installed-before-100.app`, `window-session-before.json`, `window-partial-before.json`, `retired-live.app`. 롤백 불필요.

## 5. 미완료·다음
안전한 비민감 테스트 대화의 **공식 메뉴가 실제 열린 시점**에 AXURL 후보와 네이티브 AXWindow 연결을 검증. 제목만으로 ID를 가정하지 말 것. 이후 고유 ID 저장·독립 네이티브 창 생성·제목/본문/기존 창 보존 E2E. 현재 AX raw8 중 완전 인식3, 부분5, 미식별3이므로 Restore All 강제 실행 금지. 정상 Quit→relaunch→Restore All **E2E 미완료**.

## 6. 사용자 조치
현재 없음. 정상 진행이므로 `notification_destination=windows-main` **Windows-only**; Telegram 미발송. 알림 접수/독립 조회 결과는 CURRENT.md 후속 기록. 화면 표시 성공 미검증.
