# CURRENT — ChatGPT Window Title Helper / macOS

**Updated:** 2026-10-17 KST (chat handoff, user requested new conversation due to maximum chat length).

**Canonical authority:** GitHub `harshlad79/chatgpt-window-title-helper`; feature branch `feat/macos-adaptive-title-helper`; **Draft PR #3**, unmerged; latest *pre-handoff* HEAD `00acb536f5eb031b5c1067ceb70a5ab621fc22ac` (documentation). Verified deployed **source commit** `e7f0e5a5a65044e6ca32d7b01d6a65c5617810c0`. Do not equate later documentation HEAD with installed binary. Check current GitHub branch, PR and Mac runtime afresh before any additional implementation.

## 1. Current user-visible truth (newest, authoritative)

**The owner just confirmed: "보조패널은 이제 잘 보여."** The macOS Dock ChatGPT context-menu sidecar is now visibly working after the normal-Quit/relaunch regression fix. Do **not** continue diagnosing the old "no overlay" report as an ongoing issue without new evidence.

**NOT YET VERIFIED:** The owner has **not** confirmed clicking `마지막 창 모두 복원` (Restore All) and watching the actual saved conversations reappear as separate native windows. Neither the integrated button callback nor the actual normal-Quit/relaunch → one-click restore-all round trip has been established end-to-end. The next task is to validate this specific UX (prefer a user manual click while Dock menu is open, avoiding a separate Probe app which dismisses the menu), gather results and fix only confirmed faults.

The standard *per-conversation on-window title overlay* is a separate overlay and can legitimately be absent while ChatGPT displays a generic new window with no loaded AXWebArea conversation. Do not confuse it with the **Dock-menu sidecar**, which the owner has now confirmed visible.

## 2. Product goal and accepted behavior

- **macOS first.** Display a second independent panel adjacent to the native ChatGPT Dock right-click menu; do not modify the native Dock's ambiguous identical `ChatGPT` menu labels. Current open-window buttons switch to the correct actual native ChatGPT AXWindow, previously owner-confirmed.
- The top section is currently open conversation windows; position can be left/right of native menu and does **not** need item-by-item alignment. Their order can follow AXWindows (ChatGPT already returns recent activation order); no custom sort requested.
- Below, show **the last session's complete open-window set** (not a lifetime list of every historical conversation). Preserve it for **both normal Quit and abnormal termination**. On restarting ChatGPT, display missing titles and a single **`마지막 창 모두 복원`** button. Bulk is the default; individual entries support activation of already-open or opening a missing conversation as needed.
- Each missing chat is restored in its **own newly created native window**. Restore already-open windows only once. Progress (completed/total, failures) and Cancel (after current in-flight action) are implemented. Do not bulk restore automatically on launch; only upon explicit button action.
- Dock menu is visibly opened as part of user-triggered restore. Research found **no verified invisible/deep-link route** to arbitrary prior conversations, so fallback is the verified AX menu sequence. Do not derive fake `codex://threads/<title>` URLs.
- A duplicate title cannot identify a specific chat safely. Only exact unique matches in Dock Recent can be auto-selected. No message submission, external ChatGPT binary patch, injection, SIGUSR1, or native inspector writer.

## 3. Native action E2E verified before handoff

Using signed Accessibility-approved Mac TitleAXProbe:
1. App menu `파일 → 새 창` uniquely exposes enabled AXMenuItem with AXPress; issuing it increased ChatGPT native AXWindows **1 → 2** and preserved the original window.
2. Locate the ChatGPT Dock `AXApplicationDockItem`, invoke `AXShowMenu`, then `Recent → second More` (because there are two distinct `More` items), locate the **unique exact title** AXMenuItem and invoke AXPress. It changed only the newly-created window title to that conversation; AXWindows remained **2**, old window's different conversation title remained unchanged.
3. Owner confirmed in a separate test that Dock Recent opened the selected chat **with normal conversation body**. Do not overclaim the combined newly-created-window body E2E beyond window-title/window-count proof.
4. Original Dock submenu contained 77 items in one run and 59 in another. No usable per-conversation AXURL or unique AXIdentifier; duplicates do occur.
5. Click-to-raise of current-window sidecar items was owner-confirmed before restore history work.

## 4. Implemented source and tests

Relevant canonical files:
- `macos/ChatGPTTitleHelper.swift`: AX observer and title cache, PID and recovery logic, UI callbacks; native writer remains compiled out by default.
- `macos/DockMenuSidecar.swift`: separate NSPanel beside Dock menu, current windows + last session missing titles + Restore All.
- `macos/WindowSessionHistoryStore.swift`: atomic local JSON `~/Library/Application Support/ChatGPTTitleOverlay/window-session-history.json`, owner-only mode **0600**, complete title census and `previousSessionOpen`, 12-second normal Quit window-shrink grace; `hasPendingRestart(pid:)` added by latest fix. This file stores titles, not unique chat IDs/messages.
- `macos/DockRecentWindowRestorer.swift`: exact unique-title guard; native New Window then Dock Recent, new-window identity/caption and preserved-original validation.
- `macos/WindowSessionRestoreQueue.swift`: serial ordered restore, skip open titles / de-duplicate names, reject concurrent starts, progress and cancel.
- `macos/RestoreProgressPanel.swift`: floating progress and cancel UI.
- `macos/tests/main.swift`, `macos/tests/verify_native_sync.py`, `macos/build-title-helper.sh`, `macos/tests/run.sh`.

Latest patch `e7f0e5a` passed **69 Swift test assertions**, full optimized Swift app build, original legacy `NativeTitleSync` byte-identity preservation test, signed installed bundle. Earlier commits `25a738d` introduced history/individual recovery, `e5e0104` introduced bulk restore, `fb56f4a` handles zero native windows, `1db37e7` fixed partial AX cache and 0600 migration.

No Windows source touched, no PR merge. Keep Windows and legacy class unchanged.

## 5. Latest regression and fix (critical to not repeat)

Owner normally quit and relaunched ChatGPT. Original ChatGPT PID **35112 → 70502**. TitleHelper stayed alive but original helper `refresh` returned `knownWindows=0` because the restarted app exposed a **generic AXWindow titled ChatGPT**, without a loaded conversation AXWebArea. Saved JSON remained intact: `appPID=35112`, `lastCompleteOpen=3`, `previousSessionOpen=0`. The previous code erroneously called `dockSidecar.updateHistory([])` for every incomplete AX title cache and blocked Restore All on that cache, causing the Dock sidecar itself to disappear.

**Fixed in `e7f0e5a5a65044e6ca32d7b01d6a65c5617810c0`:**
- Detect saved prior PID vs running PID using `hasPendingRestart(pid:)`; **show last saved titles even when current conversation titles are not yet available**. Do not silently erase saved session.
- Before restoring, activate existing ChatGPT, wait ~850ms, obtain fresh AX app/window list and cautiously detect existing titles. Allow a single generic starter window; reject several unidentified windows or AX errors rather than creating duplicates.
- Surface preflight failures to an NSAlert; no invisible failure.
- Runtime readback: signed new helper **PID 94099**, running ChatGPT **PID 70502**, `history-restart-pending pid=70502 saved=3`, `dock-sidecar-visible rows=0 history=3`; signed AX inspection observed a real sidecar NSPanel with **four buttons** (3 saved chat titles + Restore All).
- **Owner has now additionally confirmed the sidecar is visible.** This is a user-visible validation for the panel, **not** an end-to-end Restore All proof.

One earlier attempt to AXPress the sidecar Restore All button from a separately launched/signed Probe failed because launching Probe dismissed the native Dock menu. Another same-process attempt likewise did not retain the menu; `BULK_UI_E2E windows=0; blocked=buttonCount=0`. **No Restore All action occurred in those failed diagnostic attempts.** Do not reinterpret them as failed restoration.

## 6. Actual runtime / rollout references (snapshot; re-check if changed)

- Worker: **MacMini2**, TheCompany Dev `macos-main`. ChatGPT app `/Applications/ChatGPT.app` and signed overlay `~/Applications/ChatGPTTitleOverlay.app`.
- Original root checkout `/Users/harshlad/_Project/chatgpt-window-title-helper-macos` has previously held unrelated dirty local edits; **never reset or overwrite**. Use fresh isolated detached worktrees at exact canonical GitHub SHA.
- Latest rollout clean worktree documented: `/Users/harshlad/_Project/titlehelper-restart-verified-e7f0e5a5a65044e6ca32d7b01d6a65c5617810c0`.
- Rollback backup: `.../artifacts/macos/backups/titleoverlay-before-event.9XIfHTsP` in that worktree; check on Mac.
- Dev runtime control path: `thecompany_call_tool(operation="invoke", arguments={node_id:"macos-main",worker_tool:"run_command",backend:"python:subprocess",project:"chatgpt-window-title-helper",procedure_key:"macos-title-helper-live-readonly",tool_arguments:{program:"bash",args:["-lc","..."],timeout_seconds:20}})`. Read installed Dev skill `skills://plugins/dev-6ac812ad55408191a6adbccbda6b87c2/thecompany-core-next` and use `thecompany_status`, matching `get_latest_success` before substantive tool calls. GitHub connector owns repo, source, commits and PR. Use named signed deployment procedure `macos-package-title-helper-certificate-deployment` only after source verification.
- Dev Mac signed package invocations have repeatedly returned an outer **failed** after about **60 seconds** without worker error. In several cases, **read-only follow-up proved actual successful install/signature/backup/new PID**. Therefore NEVER blind-retry a potential side-effecting deployment; inspect installed files, code signature, process and backup first.
- Local store: `~/Library/Application Support/ChatGPTTitleOverlay/window-session-history.json` is sensitive title metadata; never print raw titles/tokens to logs or commit the JSON to GitHub. Read sanitized counts/hashes only.

## 7. Next conversation: prioritized checklist

1. Verify current canonical GitHub PR #3 feature HEAD, inspect this CURRENT document and `macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md`, check real Mac current helper PID / ChatGPT PID / signed binary / last session JSON and logs **read-only first**. User-visible panel is confirmed working; avoid restarting ChatGPT or destroying session.
2. **Primary unresolved E2E**: Have owner **manually click `마지막 창 모두 복원 (3)` in the visible sidecar**, if still present, while not launching another Probe app that dismisses Dock menu. Collect whether ProgressPanel appears and each separate ChatGPT window opens, inspect sanitized `history-bulk-` and `history-restore-` logs, AXWindows identities and saved session state. If it fails, diagnose minimal confirmed cause and fix within feature branch, build/tests/live verify.
3. Check for hidden defect in the restore controller: the generic starter window remains and bulk restore creates separate new ones; ensure results, counts and semantics actually match owner intent. Prevent duplicate chats. Handle "Dock menu closes on clicking sidecar" UI interactions carefully; do not press random menu entries.
4. Optional research if failure: accessibility timing, Dock submenu availability after new window, foreground AX preflight, exact title identity and whether the native Dock Recent menu changes across process launch.
5. Update this document after each actual checkpoint. Preserve Draft PR #3; no merge to main unless expressly approved. Send completion notification to Windows via existing TheCompany Dev mechanism when practical.

## 8. Key supporting evidence / read order

- [Normal Quit / relaunch regression and repair](../../macos/NORMAL_QUIT_RELAUNCH_OVERLAY_RECOVERY.md)
- [Last session bulk restore design and installed version history](../../macos/DOCK_LAST_SESSION_BULK_RESTORE.md)
- [Native separate new window and Dock Recent proof](../../macos/DOCK_SESSION_HISTORY_RESTORE.md)
- [Dock Recent AX menu feasibility](../../macos/DOCK_RECENT_REOPEN_FEASIBILITY.md)
- [Left sidebar AX conversation identity investigation](../../macos/SIDEBAR_CONVERSATION_LINK_AX_INVESTIGATION.md)
- [Draft PR #3](https://github.com/harshlad79/chatgpt-window-title-helper/pull/3)

**Handoff status:** SIDE PANEL VISIBLE (**confirmed**); RESTORE ALL FULL E2E (**unverified**). Next task is user-initiated live Restore All click, not a new architecture discussion.
