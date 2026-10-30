# macOS ChatGPT native new-window route — static audit (2026-10-30, 82차)

**Status:** Read-only installed-app bundle evidence. **No ChatGPT conversation route has been shown to open in a separate native window.** No UI action, IPC injection, TCC change, ChatGPT restart, or message submission was performed.

## Scope and authority

- Runtime: `macos-main`, installed `/Applications/ChatGPT.app/Contents/Resources/app.asar` (640,530,938 bytes).
- Tool: TheCompany **core_dev** Control `invoke` → `macos-main` `python:subprocess/run_command`, read-only Python `mmap.ACCESS_READ`. The bytes belong to the installed application, not the GitHub source.
- Original ChatGPT PID 27828 and TitleHelper PID 36179 were alive before the audit. Signed Helper verified; history SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159`, mode 0600.
- All offsets and minified symbols below are **specific to this installed bundle**, not a supported public API contract.

## New findings (code evidence; not runtime navigation proof)

1. At ASAR byte offset ~12,722,145, an Electron IPC branch handles `type === "open-in-new-window"`. It first checks `Z7(o.path)` and then calls `await y(o.path, BrowserWindow.fromWebContents(sender) ?? undefined)`. This is evidence of a guarded **new native BrowserWindow** path for some *internal app routes*, not permission to invoke it externally.
2. At ~12,727,208, `Z7(e)` accepts a path if `i.ao(e) || Y_t(e) || m.f(e) != null`. The audited `Y_t` recognizes selected `/o/` or `/dots/` routes, excluding reserved destinations. The allowed route families of `i.ao` and `m.f` have **not** been proved to include `/c/<conversationId>`.
3. At ~71,888,551, a thread context menu dispatches `open-in-new-window` with a thread-derived path, but the `openThreadInNewWindow` command definition has `commandMenuFeature: "codex"`. **Do not infer this works for ChatGPT conversations.**
4. At ~71,168,962, a space-page menu also dispatches `open-in-new-window` with `/space/` or `/spaces/` routes. This supports the conclusion that the IPC handler is not specifically a ChatGPT conversation restorer.
5. The ChatGPT conversation sidebar's `open-in-chatgpt` item has `href` and routes via `open_in_browser_bridge` (around ~63,922,915). It is **browser routing**, not proof of separate native window creation. The bundle also contains `routeKind: "chatgpt-thread"`, but this alone does not establish `Z7("/c/<uuid>")` acceptance.

## Measured assertions

A separate read-only `mmap` static-check script checked seven independent structural conditions on the installed ASAR. **7/7 PASS**, Mac Worker exit 0, 1,310ms, request `8181e98e-d021-408c-a6f5-8b643e2b02ae`. No ChatGPT window action was attempted. The seven checks are: BrowserWindow handler, guard, sidebar href, browser bridge, Codex command gate, space-page dispatch, ChatGPT route kind.

Earlier independent read-only calls:
- `7a2ca876-b016-4de7-8f0b-6e0de9101897`: live process/signature/history/log baseline, exit 0, 819ms, bash PID 83171.
- `9e81f8f4-c5f0-4817-9ae2-fd8fa46662e0`: ASAR targeted keyword inventory, exit 0, 14,377ms, bash PID 83910.
- `6428dc3e-ec93-418d-82b8-8abb48ec3965`: handler and route-guard source context, exit 0, 12,362ms, bash PID 85302.
- `3a64f697-eb0a-4267-832c-ccab8fd26982`: call sites, Codex-only command gate, `/o/`/`/dots/` validator branch, exit 0, 13,162ms, bash PID 85960.

All five Dev calls used Control `python(pid=646420)` → `control.invoke` → `macos-main` node-agent `python(pid=5070)` → `python:subprocess/run_command` → `bash(pid=<listed>)`; exact `mcp_path` returned for each, all outer/nested `completed`, no task_id, no timeout. Worker argv was `/bin/bash -lc <read-only Python mmap or process/status script>`, timeout 20/30/40/45/30 seconds respectively; worker cwd was agent deployment directory [private]. No OpenAI preflight safety block, Dev rejection, or Mac Worker failure.

## Safe next experiment / stop conditions

1. In read-only source analysis, trace `i.ao` and `m.f` route validators to determine whether **ChatGPT `/c/<UUID>` or `/g/<slug>/c/<UUID>`** can ever pass `Z7`. A passing validator is **necessary but not sufficient** for actual conversation restore.
2. Find an independently identifiable disposable, non-sensitive test conversation and a supported **user-facing** native action for opening that exact chat in a new window. Do **not** send raw IPC, inject code, or press unknown owner-conversation actions to force this.
3. Preserve full native AX window baseline (including minimized/unknown) before any UI test. After user-facing action, verify a **new AXWindow identity**, old windows unchanged, target title **and body** after bounded asynchronous wait. Distinguish browser tab from native window.
4. If no supported native route is found, retain guarded Dock Recent fallback with explicit missing/duplicate failures; do not represent a browser `href` as native restore success.

**Rollback:** None. This audit changed no source or runtime. PR #3 remains Draft/unmerged. Windows and NativeTitleSync unchanged.


## 83차 — route guard imports resolved; ChatGPT conversation route excluded (2026-10-30 KST)

**New conclusive static finding for the installed bundle only:** The native Electron `open-in-new-window` IPC handler **does not accept the ordinary ChatGPT conversation route** `/c/<UUID>` (nor `/g/<slug>/c/<UUID>`) through its `Z7` route guard. This is a **static exclusion**, not a live native-window test. Do not attempt direct IPC invocation or treat a browser `href` as an accepted native route.

The ASAR header was parsed read-only (pickle fields `4,6084112,6084108,6084102`); the relevant main module is `/.vite/build/main-0FVbxCQU.js`, absolute byte offset `8054231`, size `5082075`. Its imports resolve:
- `i=require("./src-CTNXdakG.js")`; exported `i.ao` is `sn(e)`. The actual `sn` recognizes `/`, `/space`, validated `/space/<id>` or `/spaces/<id>`, `/local`, `/remote`, `/plugins`, and selected `/skills/...` routes. `Mt="/local"`, `It="/remote"`. **No `/c` or `/g/.../c` family.**
- `m=require("./desktop-open-path-queue-tez0sDbS.js")`; exported `m.f` is `s(e)`, which recognizes **only** `/browser/handoff?` with validated `thread_id` and `tab_id` parameters.
- `Y_t(e)` recognizes selected `/o/<id>` and `/dots/<id>` paths.
- Therefore `Z7(e)=i.ao(e)||Y_t(e)||m.f(e)!=null` rejects a direct ChatGPT `/c/<UUID>` route under the installed app's audited definitions. This does **not** exclude a different supported native UI route or future app version.

**Reproducible version-pinned test:** `macos/tests/verify_native_new_window_route_guard.py` (source commits `3368221a`, corrective `6318a671`, `b3e72515`). The **exact fetched GitHub source** was run read-only on `macos-main` through Dev Control; final **10/10 static assertions PASS**, worker exit 0, request `008f4962-9d1d-453d-941e-f0e5e44c9e47`. SHA256 prefixes of the three installed modules: `fad45aa7d81de6fe`, `8bef484d79c728e9`, `5699e72f3d3c1db5`. No Electron code was executed; the test inspects byte strings and fails closed on changed modules. Earlier exploratory 10/10 check: request `f8fb122d-58b1-4db7-a57c-e8646e9f6fdc`, exit 0.

**Failure → correction, not hidden:** ASAR header first attempt `dc42e540` used an incorrect file seek (Python printed `JSONDecodeError` while shell exit remained 0); corrected header parse `e2d5a1fd` found the actual module. A first exploratory export-regex lookup `1fa61c57` returned `not_found` despite worker exit 0; direct exact substring lookup `d464a748` identified `i.ao→sn`. First committed static test `46b33f75` exited **1**, 8/10 due to erroneous escaped backticks in test literals; corrected test `caa52c43` exited **1**, 9/10 due to an escaped dollar sign in the literal `${i}`; final corrected source `008f4962` exited **0**, 10/10. These are **Mac Worker test-script errors**, not OpenAI safety preflight or Dev Control rejection; earlier successful exploratory assertions do not erase the two failed test runs.

**Tool-call evidence, Dev only:** All calls were `thecompany_call_tool(operation=invoke)`, `node_id=macos-main`, `worker_tool=run_command`, `backend=python:subprocess`, `project=chatgpt-window-title-helper`, `procedure_key=macos-title-helper-live-readonly`, `tool_arguments.program=/bin/bash`, `args=["-lc",<read-only Python ASAR header/mmap/import/guard script>]`, timeout 20–30 s, Worker cwd `/Users/[비공개]/Library/Application Support/TheCompany/deploy/core-4k-release-4f5e0212`. Exact returned `mcp_path` common prefix: `control-n150/thecompany-chatgpt-mcp:python(pid=754214) -> control.invoke -> macos-main/thecompany-node-agent:python(pid=5070) -> python:subprocess/run_command -> bash(pid=<listed>)`; `mcp_trace` has the same Control/agent/execution PIDs. No task_id issued. Individual `request_id short / bash PID / exit_code / mcp_elapsed_ms / purpose`:
- `0579514b / 13962 / 0 / 860 / Z7 and nearby route symbols`
- `d956dea5 / 14989 / 0 / 400 / candidate declarations`
- `dc42e540 / 15253 / 0 / 511 / initial ASAR header parsing (logical failure)`
- `e2d5a1fd / 15454 / 0 / 966 / corrected ASAR index`
- `876b1fd8 / 15678 / 0 / 605 / main module imports`
- `9147777c / 15904 / 0 / 604 / two imported module exports`
- `1fa61c57 / 16069 / 0 / 485 / regex lookup inconclusive`
- `d464a748 / 16247 / 0 / 586 / exact export symbol sn`
- `5c7ebeec / 16426 / 0 / 510 / /local and /remote constants`
- `f8fb122d / 17538 / 0 / 754 / independent 10/10 exploratory assertions and baseline`
- `46b33f75 / 18534 / 1 / 781 / committed test first run 8/10`
- `caa52c43 / 18913 / 1 / 608 / corrected test 9/10`
- `008f4962 / 20020 / 0 / 609 / corrected exact GitHub test 10/10`

All Dev outer/nested calls completed, including the two Worker assertion failures; `exit_code` is the decisive test result. GitHub `fetch_file/create_file/update_file` are source-only connector calls (no Control/Worker, no GitHub connector PID/request path exposed). No operating MCP, Work/Codex quota, TCC bypass, injection, UI click, or window creation.

**Runtime preservation at final exploratory baseline:** ChatGPT PID `27828` and Helper PID `36179` alive; Helper `codesign --verify --deep --strict` PASS; session JSON SHA256 `78772da251d30948b688b4c33f58b1d9d63da609b45098276b289552bf974159`, mode 0600, unchanged. No deployment or rollback needed. Native AX count, screenshot, new conversation ID, body rendering and complete restore E2E were **not tested** this run.

**Decision / next:** Stop treating `open-in-new-window("/c/<UUID>")` as a candidate for this installed version. Investigate **supported OS open-url / deep-link handling and native ChatGPT UI** read-only, especially whether exact conversation routes can be consumed through a legitimate user-facing action. Only if a disposable test chat and full AX baseline exist, perform one non-destructive UI navigation and verify independent AXWindow identity, title, body, original-window preservation and bounded asynchronous completion. Otherwise retain the guarded Dock Recent fallback with explicit missing/duplicate failures. PR #3 remains Draft/unmerged; Windows and NativeTitleSync unchanged. No OpenAI pre-dispatch safety block, so no `tool_boundary` Experience event.
