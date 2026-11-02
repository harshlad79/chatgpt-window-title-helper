# 97차 — 중복 열린 창 제목 복원 사전검사 강화 (2026-10-31 KST)

## 1. 제목·일시
ChatGPT Window Title Helper macOS / 마지막 창 모두 복원 / 2026-10-31 01:19–01:25 KST.

## 2. 전체 상태
**소스 수정·MacMini2 전체 Swift 테스트/ARM64 빌드 PASS. 실제 E2E 미완료.** 설치 Helper는 교체하지 않음. 기존 ChatGPT 앱·창·세션 보존.

## 3. 이번 회차 변경 및 근거
- 시작 GitHub HEAD `66d94e8532e3a09019ccd7b75e07863d0762caa4`; canonical `harshlad79/chatgpt-window-title-helper`, `feat/macos-adaptive-title-helper`; PR #3 open/Draft → `master`, 미병합. 필수 `docs/continuity/CURRENT.md`, `macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md`, `macos/DOCK_LAST_SESSION_BULK_RESTORE.md` 원문과 공통 Rulebook 원문 조회.
- **문제:** `freshOpenConversationTitles`는 네이티브 AXWindow 두 개가 동일 제목을 반환해도 두 제목을 그대로 복원 큐에 넘김. 큐는 `Set(alreadyOpen)`으로 같은 제목을 하나로 취급하므로 서로 다른 실제 대화를 이미 복원된 하나로 오판할 위험. 제목은 고유 ID가 아님.
- **수정:** `WindowRestorePreflightPolicy.hasAmbiguousOpenTitles` 추가. 복원 전 실제 AX census의 열린 제목 중복 발견 시 모든 단일/일괄 복원 진입을 **fail-closed** 처리, `history-restore-blocked reason=duplicate-open-title` 로그. 고유 ID를 추측하거나 기존 창을 닫지 않음.
- 소스 커밋: `c7166d760a706bdfad7e696556394859c7ca6ac6` (`WindowSessionRestoreQueue.swift`), `34bd2991c9fcf3d5903c6ee790e2caba75bbbebd` (`ChatGPTTitleHelper.swift`), `ddd036f181b5e917e826dec54d5ac072250621c6` (`macos/tests/main.swift`).
- 새 회귀 검증 3개: 서로 다른 제목 허용, 동일 제목 차단, 빈 제목 목록 중복 아님. **정확한 SHA `ddd036f1`의 격리 clean worktree**에서 `bash macos/tests/run.sh` **exit0**: NativeTitleSync byte-preservation PASS, TitleWorkScheduler14, session54, bulk86, asynchronous verification95, focused-menu29 assertions PASS; ARM64 optimized `BUILT artifacts/macos/ChatGPTTitleHelper`. 빌드 SHA256 `28dfcc3c886e296d06d2db301d0393abcc08166aa0707422f91f5e6e7d32cc8f`. Swift deprecated API 경고만 있음. **실제 메뉴 AXURL / 독립 창 본문 / 전체 E2E는 수행·검증하지 않음.**
- 실제 Mac 런타임 읽기 전용: ChatGPT PID **27828**, 설치 Helper PID **2124**, Helper codesign strict PASS. 원본 history SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159`/0600/553 bytes **불변**. history `appPID=501`, `lastCompleteOpen=3`, `previousSessionOpen=5`; 별도 partial `appPID=27828`, raw AXWindows=8, known entries=3, 최소화 3(지난 census), 나머지 **5개 미식별**. `appPID` 불일치는 현재 완전한 AX census가 없어 과거 저장본이 유지된 상태이며 실제 '마지막 세션'의 신선함을 입증하지 못함. 무리한 복원 금지.
- Dev macOS 화면 캡처: Terminal 전면, 공식 ChatGPT 대화 메뉴 미개방. Helper 로그 `history-restart-pending saved=3`, `ax-focused-menu-sampler foreground=false`; URL 후보 실측 조건 미충족. 화면 픽셀·개인 대화 제목·URL·ID는 GitHub에 첨부하지 않음.

## 도구 호출·실행 경로
GitHub connector (Control/Worker 미경유): `fetch_file`(필수 3문서/Rulebook/Swift/테스트/배포 기록), `get_pr_info`(#3/#4), `search_branches`(page_size100, cursor Ng 소진), `compare_commits`(4개), `update_file`(소스 3건), `create_file`(본 원장), `update_file`(CURRENT). GitHub 커넥터는 request_id/mcp_path/PID/elapsed/exit_code 미제공.
TheCompany **core_dev** `thecompany_status`, `thecompany_describe_control_operation(execute/enqueue_notification/get_notification)`, `thecompany_capture_screen(node_id=macos-main,mode=desktop,max_width=1100)`: read-only, 화면 조작 없음, capture request_id/mcp_path/PID 미제공.
Mac Worker 공통 공개 인자: `thecompany_call_tool(operation=execute, arguments={node_id:macos-main, project:chatgpt-window-title-helper, backend:python:subprocess, worker_tool:run_command, tool_arguments:{program:/bin/bash,args:[-lc,<아래 목적별 셸 스크립트>],timeout_seconds:18–28}})`. 일부 읽기 전용 호출은 `procedure_key=macos-title-helper-live-readonly`. cwd=[비공개], task_id 미발급. 실제 공통 `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=772807) -> control.execute -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<각 실행>)`; 모든 호출 outer/nested `completed`, timed_out=false. 아래는 request_id 앞 8자 / Worker bash PID / elapsed ms / 실제 exit_code / 목적:
1. `e772e6bb` /73682/1200/0: PID·서명·세션·로컬 dirty checkout 확인(원본 checkout 변경 금지).
2. `44eb5d0d` /74674/585/0: Helper 로그와 별도 partial session read-only 확인.
3. **`58ca44bc` /75635/4905/**1**: 격리 테스트 준비 스크립트에서 bash `set -u` 아래 정의되지 않은 `sha` 변수를 참조. **Mac Worker 명령 실패**, OpenAI 사전 안전검사나 Dev MCP 거절 아님. 이 시도는 git fetch까지만 수행, worktree 생성·테스트 미실행.
4. **수정 후 `cc7c1a19` /75805/2141/0:** SHA를 literal로 고정, 이미 fetch된 canonical SHA 검증, 새 격리 worktree 생성, background 테스트 PID75826 시작. 원본 dirty checkout 수정·reset 없음.
5. `727ed39c` /75908/230/0: 테스트 진행 중.
6. `d90714a3` /75985/217/0: 테스트 중 session54/async95 PASS.
7. `5a4d4e73` /76075/253/0: focused-menu29 PASS, ARM64 빌드 진행.
8. `5aebda44` /76113/403/0: 빌드 진행, SHA 확인.
9. `2600c698` /76863/242/0: Swift compile 진행.
10. `aa5da13a` /76937/167/0: Swift compile 진행.
11. `cd456da8` /76994/1574/0: Swift compile 진행.
12. `dd264a16` /77066/290/0: Swift compile 진행.
13. `703c6cea` /77132/8447/0: Swift compile 진행.
14. `d7597da5` /77287/7595/0: Swift compile 진행.
15. `b2cce41a` /78059/7418/0: Swift compile 진행.
16. `c0622782` /78176/351/0: Swift compiler CPU90%, 정상 진행.
17. `4e61bbbd` /78213/12421/0: deprecated warning, 빌드 진행.
18. **`7d5bb153` /78554/10314/0:** background test exit_code 파일 **0**, `BUILT` 확인. 앞선 폴링 exit0을 테스트 성공으로 오인하지 않음.
19. `f85ca2b1` /79373/751/0: SHA·clean worktree·원본 ChatGPT/Helper PID·서명·세션 불변 최종 확인.
위 개별 실행은 전부 동일한 Dev Control 경로; 실제 PID는 각 행의 값. `mcp_elapsed_ms`는 서버 측정치. 셸 실패 1건은 수정·재호출로 복구, 안전 차단 우회 없음.

## 원격 작업 브랜치
GitHub `search_branches` 6개, cursor `Ng` 2페이지 빈 배열. `master`, 장기 `dev` 제외. `feat/macos-adaptive-title-helper` master 대비 ahead362/behind1, PR #3 Draft/Open. `feat/approved-app-icon-20261016` ahead1/behind1이나 PR #4 **merged**(기능 미병합으로 중복 집계하지 않음). `feat/title-change-event-probe` ahead0/behind2, `fix/chatgpt-2026-title-ui` ahead0/behind7. **검증된 미병합 기능 브랜치 1개**. PR #3 병합하지 않음.

## 4. 최종 상태·기존 영향
변경은 GitHub 격리 브랜치에만 존재. **설치 Helper는 95차 서명 배포 소스 `4d69eab4` 유지**, 97차 새 소스 `ddd036f1`은 미배포. ChatGPT PID27828, Helper PID2124, 세션 SHA 불변. 원본 창·Dock·포커스·Windows 소스·NativeTitleSync·TCC·ChatGPT 앱 바이너리 변경 없음. 롤백 불필요(기존 Helper 백업 보존).

## 5. 미완료·다음
1. 실제 비민감 테스트 대화의 공식 메뉴가 열린 안전한 시점에 AXURL 후보 실측. 현재 Terminal 전면이며 메뉴가 없어 URL 부재라고 판정하지 않음.
2. PID501 저장 history와 PID27828 partial AX8/known3의 신선도·고유 ID 결손을 해결. 동일 제목·미식별 창은 복원 성공으로 집계 금지.
3. 새 native 창의 고유 URL/ID·제목·본문·기존 창 보존 → 전체 Quit/relaunch/Restore All E2E 실증. 기존 ChatGPT 종료·창 닫기 금지. 새 preflight guard는 추후 필요 시 안전 백업 후 배포 판단.

## 6. 사용자 조치
현재 없음. 이번 회차 **Mac Worker bash exit1** 1건 발생 후 허용된 인자 수정으로 정상 복구했으므로 정책상 Telegram 우선, Windows 후속 알림. 각 접수는 별도 조회 후 CURRENT에 추가 기록. OpenAI 사전 안전검사 차단 0, Dev Control 거절 0, Mac Worker 실패 1(복구됨). 운영 MCP/Work/Codex 사용 없음.
