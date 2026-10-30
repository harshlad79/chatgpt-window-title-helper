# Focused ChatGPT menu AXURL evidence probe — 2026-10-30 (86차)

## Scope and result

**Research-stage implementation; installed Helper not changed. Full Restore All E2E NOT VERIFIED.** The installed ChatGPT app statically creates a per-conversation `href` in the `open-in-chatgpt` menu action, but neither AXURL exposure nor independent native-window restoration has been established. This probe can inspect an **already open** context menu from the existing Accessibility-approved Helper process. It does not open/press menus, navigate, alter focus, read messages, or log raw titles/URLs/conversation IDs.

The existing `boundedShareControlCensus` ran only when the visible conversation count changed. On the installed Helper log (2026-10-29T21:30:58–59Z), the one-shot `ax-visible-identity` reports `checked=1/2/3`, `openOnChatGPTControls=0`, `openOnChatGPTConversationURLs=0`, while `ax-window-census` reports **raw=8**, **minimized=3**, recognized conversation titles increasing 1→3. The menu was **not shown to be open at sampling time**, so zero controls is **not evidence that the menu lacks AXURL**. These are previous AX measurements, not a current live census.

## New source (canonical GitHub feature branch)

- `macos/FocusedMenuURLProbe.swift`: bounded read-only AX-focused-element ancestor walk to an existing `AXMenu`, at most 160 nodes / 0.9 seconds; classify only exact localized `Open on chatgpt.com` labels and `AXURL` using `ConversationRouteIdentity.parse`. Emits only aggregate counts, not raw data. Missing/invalid URL is not considered a valid identity.
- `macos/tests/menu_probe/main.swift`: 12 fail-closed classification assertions (valid direct/project route, case normalization, missing/invalid/external/script URL, query rejection, unrelated/destructive labels).
- `macos/ChatGPTTitleHelper.swift`: optional 2.5-second background census **only** if `TITLEHELPER_SAFE_FOCUSED_MENU_URL_PROBE=1` and ChatGPT is foreground; serialized in-flight, logs `ax-focused-menu-url` only if a focused menu exists. **Default off.**
- `macos/build-title-helper.sh` and `macos/tests/run.sh`: include the new source and test. Original `NativeTitleSync` source and Windows code remain untouched.

**Source commits:** `34085629` new probe; `3040d00f` tests; `7520fd44` corrected CFTypeID/AXUIElement casting; `aa5c99b2` opt-in Helper integration; `3030437f` build wiring; `ed20840b` test runner wiring. The last of these is the exact isolated Mac checkout HEAD for validation. No PR merge or signed deployment.

## MacMini2 validation and failure/recovery

- First isolated source compile, Dev request `38cb76ec-6d3a-40f2-9d64-3b3c8649b860`: **Worker exit 1** (Swift rejected two `as? AXUIElement` casts as always succeeding), 5191ms. This is a Mac Worker compilation failure, **not** OpenAI preflight or Dev Control refusal.
- Corrected exact GitHub file via `7520fd44`; request `5ef33a3f-b038-4034-bb18-986c9546385f`: **Swift compile exit 0, 12/12 assertions PASS**, 6477ms, bash PID 22743.
- Clean isolated Mac clone `/tmp/titlehelper-menu-ax-86-ed20840b` at exact `ed20840b687063ee56c89f3949cc663e5c141613`: request `2ce4b3c4-a8f8-4801-ae54-746fc6d02b81`, clone exit 0, HEAD match, clean.
- Full `bash macos/tests/run.sh` request `a0405b5a-740b-4a1b-bd09-e02ca8dc4bbe`: Dev returned **DELIVERY_UNKNOWN/ReadTimeout after 60156ms**, same request reconciliation `pending/request_in_progress`, **no Worker exit code**. Do not treat this as failed compilation or success; do not blindly re-run build. Read-only inspection found Swift compiler still running. Independent execution of generated temporary test binaries via request `5f3cd82f-c370-4faa-b48a-ea34b259a0ae` gave **88 existing assertions PASS** and **12 menu-policy assertions PASS**; this verifies tests, **not** the full optimized build. `verify_native_sync.py` and bash syntax check separately PASS via request `8f1867c5-edfd-4b9c-922f-e8ec9ff24f63`.
- Final optimized binary outcome **pending read-only reconciliation** at this document creation. No app deployment, no code signing or existing Helper restart.

## Tool route and error classification

Canonical source/docs/PR/branch inventory: GitHub connector `fetch_file`, `create_file`, `update_file`, `get_pr_info`, `search_branches`, `compare_commits`; no Mac runtime action through GitHub connector. All Mac actions use TheCompany **core_dev** `thecompany_call_tool(operation=invoke)` → Control `control-n150` → `node_id=macos-main` → `backend=python:subprocess`, `worker_tool=run_command`, `project=chatgpt-window-title-helper`, `procedure_key=macos-title-helper-live-readonly`, `program=/bin/bash`, `args=[-lc,<read-only status/ASAR log analysis or isolated /tmp Swift tests/build>]`, timeout 15–60s. Worker cwd is Mac agent deployment [비공개]. Successful calls expose `mcp_path=control-n150/thecompany-chatgpt-mcp:python(pid=754214) -> control.invoke -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<per request>)`, with matching `mcp_trace`; no task_id. The DELIVERY_UNKNOWN request exposed only `control-n150/thecompany-chatgpt-mcp:python(pid=754214) -> control.invoke -> macos-main`.

**Individual Dev receipts** (short request / purpose / bash PID / elapsed ms / Worker exit):
- `dc0c824d`: Control-only `get_latest_success`, 2ms, completed, prior success verified.
- `2e4e3b67`: live PIDs/signature/session hash, 20414 / 779 / 0.
- `57a39fe5`: prior aggregate AX log, 20563 / 485 / 0.
- `8d58a81a`: installed ASAR menu source excerpts, 20755 / 676 / 0.
- `38cb76ec`: first isolated Swift compile **failure**, 22595 / 5191 / **1**.
- `5ef33a3f`: corrected isolated Swift compile and 12/12 tests, 22743 / 6477 / 0.
- `2ce4b3c4`: exact isolated clone, 23723 / 1762 / 0.
- `a0405b5a`: full suite + optimized build, PID/exit **미제공**, 60156, **DELIVERY_UNKNOWN**.
- `2535add2`: read-only compiler reconciliation, 25170 / 1105 / 0.
- `e17ac079`: read-only compiler reconciliation, 25237 / 640 / 0.
- `5d690b20`: read-only compiler reconciliation, 25338 / 503 / 0.
- `5f3cd82f`: independent existing/new test binaries, 26090 / 2708 / 0.
- `593ccfb8`: read-only compiler reconciliation, 26141 / 489 / 0.
- `8f1867c5`: NativeTitleSync byte-identity and bash syntax, 26287 / 583 / 0.
- `dba72630`: read-only compiler status and local KST clock, 26324 / 538 / 0.

**One local input-schema rejection before Control:** `get_latest_success` was first called with `tool` rather than required `operation`; no request_id/mcp_path/mcp_elapsed_ms/exit_code issued. Corrected call `dc0c824d` completed. This is a **client-side tool schema validation error**, not OpenAI safety preflight, Dev Control refusal or Mac Worker failure. **OpenAI preflight safety block: none.** No `tool_boundary` Experience required. No operating MCP, Work/Codex, TCC bypass or injection.

## Safety, rollback, next gate

At start, ChatGPT PID **27828**, Helper PID **36179**, installed Helper code signature PASS, existing session JSON SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159`, mode `0600`, 553 bytes. No user window was closed, focused, navigated or edited. This branch code is **not installed**, so rollback of installed Helper is unnecessary. If source integration fails build, revert only new probe/build/test commits on the feature branch; do not touch Windows/NativeTitleSync.

**Next:** reconcile optimized build without blind retry. After an exact signed deployment with backup and owner windows preserved, enable diagnostic **only in an explicitly safe session**, open an isolated non-sensitive conversation's official context menu (without separate Probe) and inspect aggregate `ax-focused-menu-url`. Only then consider durable ID storage and a supported native separate-window action. **AXURL live proof, independent native window, body and full Quit→relaunch→Restore All E2E remain unverified.**
