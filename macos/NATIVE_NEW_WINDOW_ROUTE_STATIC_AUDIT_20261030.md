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
