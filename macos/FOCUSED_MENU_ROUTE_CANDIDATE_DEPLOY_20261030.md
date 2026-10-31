# 95차 — 2026-10-30 23:27–23:35 KST — 후보 URL 집계 Helper 실기기 배포 및 비파괴 보존 검증

## 1. 제목·일시
ChatGPT Window Title Helper macOS — 마지막 창 모두 복원 / 95차 / 2026-10-30 23:27–23:35 KST.

## 2. 전체 상태
**GitHub 검증 소스 `4d69eab48225570c887906704411eb1d5bf5b8c8`의 후보 URL 집계 기능을 실제 서명 Helper에 배포하고 LaunchServices로 재기동. AX observer 및 기존 ChatGPT 창·세션 보존 확인. 실제 메뉴 AXURL 및 전체 Quit→relaunch→Restore All E2E는 미검증.**

## 3. 변경·검증·근거
- Canonical GitHub `harshlad79/chatgpt-window-title-helper`, `feat/macos-adaptive-title-helper`, 시작 HEAD `76a41fc190ac25b683d2e45af9d88cc3a223d0e7`, PR #3 open/Draft, base `master`, 미병합. 필수 원문 `docs/continuity/CURRENT.md`, `macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md`, `macos/DOCK_LAST_SESSION_BULK_RESTORE.md` 및 공유 Rulebook 원문 확인. Windows/NativeTitleSync 변경 금지 유지. 이번 회차 **소스 수정 없음**.
- 기존 93차의 **정확한 GitHub SHA**로 만든 격리된 clean worktree `~/_Project/titlehelper-93-4d69eab4`에서 `bash macos/tests/run.sh` 실행. `verify_native_sync.py` PASS, scheduler **14**, session **50**, bulk **82**, asynchronous restore **88**, focused menu **29 assertions PASS**; 최적화 ARM64 빌드 **exit 0**, unsigned SHA256 `d24ac2efb695404294d844188325f1afaee49c0cf332aea4acd94c7041eae9f8`. macOS deprecated API 경고는 오류 아님. `LIVE_AX_MENU_URL=NOT_TESTED`.
- 설치된 Helper의 Bundle ID `local.chatgpt.titleoverlay`, TheCompany 코드 서명 인증서, 기존 세션 파일 mode0600 및 SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159` 확인. 앱 전체와 세션을 먼저 독립 백업. 후보 앱에 위 빌드 바이너리를 넣고 `codesign --force --timestamp=none --sign <TheCompany identity>`; `codesign --verify --deep --strict` **PASS**. 서명 후보 실행파일 SHA256 `af8bc2c6dda48007ce41ba858764cf9f1fccffef42fd487b6a516d38cd7a2af1`.
- **Helper만** PID66337에 SIGTERM 후 서명 앱으로 교체. ChatGPT PID27828에는 신호·종료·메시지·포커스 변경 없음. 표준 `/usr/bin/open --env TITLEHELPER_SAFE_FOCUSED_MENU_URL_PROBE=1 --env TITLEHELPER_SAFE_AX_WINDOW_SNAPSHOT=1 -a ~/Applications/ChatGPTTitleOverlay.app`로 Helper만 재실행. 새 PID **2124**, `ax-observer-created=true pid=27828`, `ax-focused-menu-sampler heartbeat foreground=false trusted=true targetValid=true inFlight=false`. 서명 PASS, 세션 SHA/mode 유지, ChatGPT PID27828 유지. **배포 성공**.
- 기존 Helper의 AXWindow census를 새 Helper에서 다시 확인: **raw8, minimized3, recognized3** (초기 캐시 준비 중 1→2→3). 미식별 창이 있으므로 전체 창 복원 실행 금지.
- Quartz CGWindow 읽기 전용 기준선: 배포 전 **18개**, onscreen **5개**, 배포 후 **18개**, onscreen **5개**. CGWindow ID 중 14개 보존, 교체된 4개는 조사 시 **1920×30, layer0, onscreen=false**의 비표시 얇은 보조 표면. 이 4개는 사용자 대화 창이라고 간주하지 않음. **CG 18 ≠ AX 8**. 기존 주 창 CG ID 보존, 실제 AX raw8 유지. 화면 캡처 전후 Terminal 전면, ChatGPT 공식 대화 메뉴 없음. 개인 화면은 GitHub에 첨부하지 않음.
- 새 집계 기능은 유효한 ChatGPT 대화 URL 후보 **개수만** 집계. URL·ID·본문·제목은 로그에 출력하지 않으며 현재 창 ID에 결합하지 않음. 실제 `routeCandidates` 이벤트는 아직 **0건(메뉴 미개방)**. 메뉴가 없으므로 AXURL 부재로 판정하지 않음.
- **오류/복구 구분:** 최초 CGWindow Python 검사에서 `ModuleNotFoundError: No module named 'Quartz'`가 출력되었으나 Worker 자체 exit0. **Mac Python 환경 의존성 미설치에 따른 진단 내부 실패**, OpenAI 사전 안전검사 차단/Dev Control 거절 아님. 허용된 macOS Swift `import Quartz; CGWindowListCopyWindowInfo` 읽기 전용 대안으로 수정하여 CG18/ID/onscreen 기준선 및 사후 상태 성공. 기존 Helper 배포 중 Worker 오류 없음. 별도 `type=tool_boundary` 사전 안전 차단 기록 조건 미발생.

## 도구 호출·실행 경로 (시도별)
- GitHub connector `fetch_file`(필수 3문서·Rulebook·Swift/테스트·CURRENT), `get_pr_info`(#3/#4), `fetch`(정확한 HEAD tree), `search_branches`(6개 + cursor Ng 소진), `compare_commits`(4개), `search_commits`(기본 브랜치 결과이므로 feature HEAD 근거로 사용하지 않음), `create_file`(본 문서), `update_file`(CURRENT). GitHub는 Control/Worker 미경유; request_id, mcp_path, PID, elapsed, exit_code **미제공**.
- TheCompany **core_dev** `thecompany_status`, `thecompany_describe_control_operation(invoke/enqueue_notification/get_notification)`: Dev 메타데이터 읽기. `thecompany_capture_screen(node_id=macos-main,mode=desktop,max_width=1100/1000)` 2회 이미지 수신, 사용자 화면 입력·클릭 없음; request_id/mcp_path/PID/elapsed **미제공**.
- Mac 실행 전부 **TheCompany core_dev** `thecompany_call_tool(operation=invoke)`, `node_id=macos-main`, `project=chatgpt-window-title-helper`, `backend=python:subprocess`, `worker_tool=run_command`, `tool_arguments={program:/bin/bash,args:[-lc,<개별 읽기/빌드/서명/백업/Helper-only 배포 명령>],timeout_seconds:12–45}`. 읽기 전용 호출에 `procedure_key=macos-title-helper-live-readonly`. Worker cwd [비공개], task_id 미발급. **모든 아래 호출 outer/nested completed, exit_code0, timed_out=false**, 실제 공통 `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=772807) -> control.invoke -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<아래>)`, `mcp_trace` 동일.
  1. `070a8a3b` bash95162/1279ms: PID·서명·로그 첫 확인(세션 경로 최초 오기, 출력 빈 해시).
  2. `6278505e` bash95987/4153ms: 로그·실제 세션 경로·Terminal 전면.
  3. `d231211f` bash96179/1109ms: 메뉴 진단·세션 SHA 확인.
  4. `0166a541` bash96232/282ms: AXWebArea 앱 공통 URL/최소화 메타데이터 기존 로그 조회.
  5. `6076e18a` bash97277/444ms: 정확한 SHA clean worktree/설치 스크립트 확인.
  6. `530384ca` bash97367/424ms: `run.sh` background PID97375 시작.
  7. `6741eb64` bash97452/361ms: Python Quartz import 오류 확인, 빌드 진행.
  8. `e11eea80` bash97593/14817ms: Swift Quartz CG18 기준선·ID 확인, 오류 복구.
  9. `345badbe` bash98389/196ms, `c2426870` bash98574/218ms, `0c40ee2e` bash98610/12447ms, `45b84fcc` bash99474/289ms, `17c3e7d2` bash99563/20451ms: 장시간 ARM64 빌드 중복 실행 없이 상태 확인.
  10. `8b64b9e8` bash99779/264ms: **run.sh exit0**, 테스트/빌드 SHA 확인.
  11. `cb18f376` bash99856/1143ms: 기존 앱/세션 백업·별도 후보 서명·검증.
  12. `6381b0ad` bash2107/6609ms: **Helper-only 교체/LaunchServices 재시작** PASS, PID2124·ChatGPT27828·세션 SHA 불변.
  13. `1d6caa1d` bash3273/4123ms: observer·AX raw8/min3/recognized3·CG18 사후 검증.
  14. `e35ddeb6` bash3388/1926ms: 변경된 CG ID 4개는 1920×30 비표시 표면임을 검증.
- Dev Control-only 알림 `enqueue_notification/get_notification`은 알림 접수 후 CURRENT.md 후속 영수증에 기입. 수신 성공과 기기 표시 성공은 별개.

## 4. 최종 상태·기존 작업 영향
**배포 소스 `4d69eab4`**, 설치 서명 바이너리 `af8bc2c6...`, Helper PID2124, ChatGPT PID27828, AX observer 정상, 세션 SHA256 불변. 기존 ChatGPT 앱/창/대화/포커스·Windows/NativeTitleSync·PR #3 미변경. 롤백 백업 `~/_Project/titlehelper-93-4d69eab4/artifacts/macos/95-stage/installed-before-95.app`, 세션 `.../95-stage/window-session-before.json`. 필요 시 Helper만 정지 후 기존 서명 앱 복원·LaunchServices 재실행. **현재 롤백 불필요**.

## 5. 미완료·다음
실제 안전한 비민감 대화의 공식 메뉴가 자연스럽게 열린 시점에 `foreground=true`, `routeCandidates`, `conversationURLs`, `noMenu focusAvailable` 관찰. 현재 Terminal 전면이므로 사용자 앱 포커스를 강제 변경하지 않음. 메뉴 AXURL이 노출돼도 해당 URL이 **어느 AXWindow에 속하는지** 별도 검증해야 함. 고유 ID 저장 및 독립 네이티브 창 생성·제목/본문·기존 창 보존 E2E 미검증. `/c/<UUID>`는 설치된 Electron 내부 `open-in-new-window` route guard에서 정적으로 거절됨(83차), 임의 IPC/코드 인젝션 금지. Dock Recent title-only는 누락/중복 한계. **전체 E2E 미완료**.

## 6. 사용자 조치
현재 없음. 다만 Python Quartz 모듈 부재 오류가 있었으므로 정책상 **Telegram 우선, Windows 후속**으로 보고. 양 채널 독립 접수 확인 후 CURRENT.md에 기록. 표시 성공은 별도 미검증.
