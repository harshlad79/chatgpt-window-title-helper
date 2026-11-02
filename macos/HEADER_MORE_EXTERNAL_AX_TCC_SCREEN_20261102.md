# 143차 — 2026-11-02 05:20–05:23 KST — 외부 AX 권한 경계 및 화면 상태 실측

## 1. 제목·일시
ChatGPT Window Title Helper macOS — 마지막 창 모두 복원. 143차, 2026-11-02 05:20 KST 시작.

## 2. 전체 상태
**외부 읽기 전용 AX 경로 두 종류의 TCC 접근 불가 실측. 현재 ChatGPT 전면에 검색 팔레트가 열린 화면 캡처 확보. 신규 코드·설치·창 복원 없음. 전체 Restore All E2E 미완료.** 기존 앱/창/세션 유지.

## 3. 이번 수행·근거
- canonical GitHub `harshlad79/chatgpt-window-title-helper` branch `feat/macos-adaptive-title-helper` HEAD **`a3211ec1c7dd08c0153818d6fe4bda9a89b49441`**에서 필수 3문서 원문, 141/142차 상세 원장, `macos/TitleAXProbe.swift`, `macos/ChatGPTTitleHelper.swift` 조회. 공통 Rulebook `harshlad79/thecompany-core:feat/org-rulebook-experience-loop/docs/workstreams/shared-scheduled-notification-report-v1.md` 원문 조회. PR #3 **Open/Draft → master**, 미병합.
- Dev `rulebook_request(project=chatgpt-window-title-helper)`는 기존과 같은 `rulebook_project_mismatch` **Control-only 거절**. 이는 OpenAI 사전 안전검사 차단이나 Mac Worker 실패가 아님. 별도 Dev Control execute의 기존 허용 계약을 `describe_control_operation(execute)`로 조회.
- Mac `/usr/bin/swift -e` 읽기 전용 AX: `AXIsProcessTrusted() == false`, ChatGPT 프로세스 1개, `AXUIElementCopyAttributeValue(kAXWindowsAttribute)` status **-25211**, AXWindow 수집 불가. **명령 exit0 ≠ AX 성공**.
- 기존 설치 `~/Applications/ChatGPTTitleProbe.app` 및 Helper 두 앱 `codesign --verify --deep --strict` **PASS**. `ChatGPTTitleProbe.app/Contents/MacOS/ChatGPTTitleProbe inspect-window-title`는 GitHub 코드상 읽기 전용 모드이며 실제 실행에서 `AX_WINDOW_CAPTION mode=readonly trusted=false`, `blocked=accessibility-not-trusted`, 프로세스 exit0. 기존 Probe 로그를 `title-ax-probe-current.log.pre-143`으로 복사한 뒤 검사; Dock 메뉴 열기·클릭·TCC 변경 없음. **서명 성공이 TCC Accessibility 승인을 뜻하지 않음**.
- Dev `thecompany_capture_screen(node_id=macos-main,source=companion,mode=desktop,max_width=1600)`가 **실제 ChatGPT 화면 이미지** 반환. 시각 관찰: 전면 ChatGPT 창에 **검색/명령 팔레트**가 열려 있고, 대화 Header의 일부가 가려져 있음. 이 화면 상태는 Header More AX 후보 누락의 **가능한 혼란 변수**이며 134~142차 당시에도 같은 상태였는지는 **미확인**. 따라서 'More 버튼이 앱에 없다' 또는 '팔레트가 과거 0건의 확정 원인'으로 단정 금지. 이미지 자체/대화 본문은 GitHub에 게시하지 않음.
- GitHub Swift 원문 재확인: `boundedHeaderMoreCensus(window, conversationTitle: title)`는 `samples`의 named WebArea와 연결된 AXWindow를 대상으로 실행. 따라서 검색 팔레트가 열려도 named sample이 남을 수 있으며 **실제 Header 노출·상태 별도 확인 필수**. 현행 141/142차 새 parent-identity 코드는 GitHub에만 존재, 설치본은 140차.
- 사전/사후 CGWindowList 실측: ChatGPT layer0 창 **2개, IDs 15360/16252** 동일, 전면 bundle `com.openai.codex`. ChatGPT PID **10411**, Helper PID **77666** 유지. session JSON SHA256 **`f4fe834b324534ca80e6139ab43a52bccc3bf968babd998c9f19e9580726d104`**, mode **0600** 불변. 기존 창·대화·Helper 종료/닫기/덮어쓰기·AXPress·복원·메뉴 조작 없음.
- **Experience** direct Dev `type=tool_boundary` event **`f4cfce90-cc2c-4905-ada6-02659cdfe872`**, request `b6f2aad6-3eac-4644-99a3-86f4e0d1223a`, outer/nested completed/captured, 3ms. `list_experience(types=[tool_boundary],scope=project,order=desc,limit=15)` request `319a4449-869a-4c9f-ac2a-b74de28cff12`, completed, found=true, 4ms.

### 도구 호출·실행 경로와 실패→복구
1. **GitHub connector** (Control/Worker 비경유): `fetch_file` 필수 3문서, 141/142차 상세, Swift 2개, 공통 Rulebook; `get_pr_info(#3,#4)`, `search_branches(query='',page_size=100,cursor=null→Ng→null)`, `compare_commits(base=master,head=4 feature branches)`; GitHub connector 별도 request_id/PID/mcp_path/exit_code **미제공**. 6개 원격 브랜치 전수: 활성 미병합 기능 브랜치 **1개**(`feat/macos-adaptive-title-helper`, ahead534/behind1); `feat/approved-app-icon-20261016` ahead1/behind1은 **merged PR #4 squash 잔여**; `feat/title-change-event-probe` ahead0/behind2, `fix/chatgpt-2026-title-ui` ahead0/behind7, `dev` 장기 기반, `master` 기준. PR 없는 신규 미병합 기능 브랜치 **0개**.

2. **Dev Rulebook 거절**: `mcp__TheCompany_core_dev__rulebook_request(project=chatgpt-window-title-helper,request=read-only AX investigation)` request `d0fdb216-2290-4c15-9ad7-5ad1d78e0cb4`, outer/nested rejected/rejected, reason `rulebook_project_mismatch`, 0ms, `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=850940) -> control.rulebook_request`. Worker 미실행. 허용된 `describe_control_operation(execute)`로 인자 계약을 확인하고 기존 Dev 읽기 전용 작업 진행; **안전검사 우회 아님**.

3. **Dev Mac execute** 공통 인자: `operation=execute,project=chatgpt-window-title-helper,node_id=macos-main,backend=python:subprocess,worker_tool=run_command`. 공통 경로 `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=850940) -> control.execute -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> <program>(pid=아래)`. 별도 cwd는 NodeAgent 배포 디렉터리 [비공개]. HTTP200, timed_out=false:
   - `44b9d2f8-325d-4453-b8d0-1b38ae3e248f` `/bin/bash -lc` ps/ls/which, timeout15, PID78778, exit0, 269ms.
   - `8569bc9c-2fc9-467a-acf1-51e08dc9c1fa` `/usr/bin/swift -e` AXIsProcessTrusted/AXWindows read-only, timeout20, PID78837, exit0, 2484ms, **AX -25211**.
   - `9cc10a96-4b04-4e8b-90d3-1ff47808a343` `/bin/bash -lc` codesign/plutil/ps, timeout15, PID78968, exit0, 328ms.
   - `6ce661fb-6914-4bf7-a5de-d663c7b2cf56` `/bin/bash -lc` ls/grep existing helper logs, timeout15, PID79065, exit0, 262ms.
   - **도구 전 JS 조립 실패 1건:** Swift CG 검사 호출 JS 문자열 구문 `SyntaxError: Unexpected token ')'`, request_id/mcp_path/exit_code **미발급**, MCP/Worker 미실행. 인용부호 수정 후 아래 재호출 성공. OpenAI safety block 아님.
   - `ee4959d2-08df-4157-a1e7-a88712eed674` `/usr/bin/swift -e` CoreGraphics/NSWorkspace window+frontmost census, timeout15, PID79815, exit0, 1460ms.
   - `12f4a9e0-cfbb-4aee-87a8-994fb5284f62` `/bin/bash -lc` copy old Probe log + existing signed Probe `inspect-window-title`, timeout18, PID79851, exit0, 169ms, **TCC untrusted**.
   - `34b36b3a-9c7c-4c9c-9d28-dc6a87c57d5f` `/bin/bash -lc` shasum/stat/ps + Swift CG postflight, timeout18, PID80137, exit0, 2709ms; 창/세션/PID 불변.

4. **Dev screen** `mcp__TheCompany_core_dev__thecompany_capture_screen(node_id=macos-main,source=companion,mode=desktop,max_width=1600)` image returned; tool result의 request_id/mcp_path/mcp_trace/elapsed **미제공**, 사용자 화면 내용 원본 저장·공개 없음.

5. **Dev Experience direct**: `thecompany_record_experience(type=tool_boundary,scope=project)` request `b6f2aad6...`, outer/nested completed/captured, event `f4cfce90...`, 3ms; `thecompany_list_experience(types=[tool_boundary],scope=project,order=desc,limit=15)` request `319a4449...`, completed/found=true, 4ms. Control-only `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=850940) -> control.record_experience/list_experience`. Mac Worker 없음.

**분류:** OpenAI 사전 안전검사 차단 **0건**, Dev Rulebook Control 거절 **1건**, Mac Worker 실행 실패/exit nonzero **0건**, 읽기 전용 AX TCC 불허 **2경로**, JS 도구 전 구문 오류 **1건 수정 완료**. Exit0는 TCC 허용을 의미하지 않음.

## 4. 최종 상태·기존 영향
GitHub 문서만 변경 예정, Swift 소스/테스트/서명 설치/ChatGPT 앱/NativeTitleSync/Windows 소스 **무변경**. 설치된 Helper는 140차 source `19f61f3`, 141/142차 source는 미배포. Draft PR #3 미병합. 신규 설치가 없으므로 롤백 불필요; 기존 140차 백업 유지. Probe 로그 원본은 `.pre-143`으로 보존.

## 5. 미완료·다음
- **현재 대화 Header More, 고유 URL/ID, 개별 native 복원, 전체 Restore All E2E 미완료.** 검색 팔레트가 사라진 실제 대화 Header 상태의 스크린샷/AX 재검증이 필요. 기존 팔레트를 임의로 닫지 않음.
- 외부 AX는 직접 Swift/기존 signed Probe 모두 TCC 불허. 사용자가 승인하는 경우 **System Settings → Privacy & Security → Accessibility → ChatGPTTitleProbe**를 명시적으로 허용한 뒤 기존 `inspect-window-title`로 재검증. TCC 우회·코드 인젝션·새로운 Helper 설치 재시도 금지. 별도 Probe를 Dock 메뉴 열린 상태에서 실행하지 말 것.
- 이미 설치된 Helper의 읽기 전용 로그·공식 ChatGPT UI/AX 증거를 우선하고, 사용자 허용/안전한 실행 경로가 확인될 때만 추가 AX 부모 관계 진단. 사용자의 기존 창과 팔레트는 보존. 141차 차단된 Helper 배포는 우회하지 않음.

## 6. 사용자 조치·알림
외부 Probe로 추가 AX 진단을 원한다면 **macOS Accessibility에서 ChatGPTTitleProbe를 사용자 본인이 허용**해야 함. 강제/자동 권한 변경 없음. 이 회차는 Dev 거절 및 권한 차단으로 **Telegram 우선 + Windows 별도 독립 본문**을 Dev Control `enqueue_notification`으로 발송하고 `get_notification` 접수 영수증 확인 예정. 접수와 실제 기기 표시 분리. 예약 유지.

### 후속 GitHub 검증 오류·복구 (05:24 KST)
- `mcp__GitHub__fetch_commit` 최초 호출에서 실제 스키마가 요구하는 `repo_full_name,commit_sha` 대신 `repository_full_name,sha`를 전달해 **커넥터 인자 검증 단계에서 거절**. MCP/Worker 실행 영수증·request_id/mcp_path/exit_code 미발급. OpenAI 안전검사 차단 아님.
- 정확한 스키마 `fetch_commit({repo_full_name:"harshlad79/chatgpt-window-title-helper",commit_sha:"55e56c129bf44e467a56a8a17d4e518ee642ef6e"})`로 수정해 재조회 성공. `get_pr_info(#3)`는 head `55e56c129bf44e467a56a8a17d4e518ee642ef6e`, Open/Draft→master 확인; `fetch_file(CURRENT.md,start_line=1,end_line=17)`는 143차 본문 반영 확인. 이 오류는 Mac Worker/TCC 차단과 무관하며 복구 완료.
