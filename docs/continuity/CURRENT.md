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

## 9. 2026-10-17 diagnostic rollout after owner Restore All failure

Owner actually clicked Restore All. Mac event log 2026-10-16T19:51:54Z (2026-10-17 04:51:54 KST): request accepted with total=3, item progress failed 1/3, 2/3, 3/3, completed=3 failed=3 cancelled=false at 19:52:01Z. Two later individual attempts at 19:57:31Z / 19:57:43Z were blocked `foreground-AX-incomplete`. The queue had previously ignored each restore callback's reason, making exact per-item root cause impossible to recover from these logs.

GitHub commits `18689696821337320575112cd8f616ac77c4ed48` and `ccfb8aa34a824778c5ac8658807456ed3e19bbce`: add `WindowSessionRestoreQueue.onResult(title, success, reason)` and sanitized `history-bulk-item ok=... title=<fingerprint> reason=...` diagnostics in `ChatGPTTitleHelper.swift`. No restore semantics intentionally changed, no Windows/NativeTitleSync edits, no merge. Exact detached MacMini2 source SHA `ccfb8aa` clean; Swift tests/build invoked and optimized executable generated at 2026-10-17 05:30:46 KST. Mac remote tests/build call returned `delivery_unknown` (~60 s), but subsequent read-only check confirmed the build process and generated executable. Do not claim captured test-assertion count from that timed-out invocation.

Signed packaging attempted exactly once; Dev MCP again returned `DELIVERY_UNKNOWN` (~60 s). Read-only reconciliation verified installed signed bundle (`codesign --verify --deep --strict` success), new helper PID 234, original ChatGPT PID 70502 preserved, new executable timestamp 2026-10-17 05:32:19 KST, rollback backup `artifacts/macos/backups/titleoverlay-before-event.W8kiKRkS` in isolated worktree `/Users/harshlad/_Project/titlehelper-diagnostic-ccfb8aa34a824778c5ac8658807456ed3e19bbce`. History remains restart-pending with 3 saved titles. This verifies deployment, NOT full restore success.

**Next:** Owner manually click Restore All again while Dock sidecar is shown, without a separate Probe. Immediately read sanitized `history-bulk-item` events to locate exact failure stage. If needed fix AX menu interactions, test on exact GitHub HEAD, sign and redeploy, then E2E verify separate windows and original window preservation. PR #3 remains Draft/unmerged. Do not quit ChatGPT or close owner windows.

## 10. 2026-10-27 KST — PID-aware session selection implemented, tested, deployed; E2E still open

**Canonical branch before this documentation commit:** `987fccb8456ea0e7847cfcd00239b905ce270c24`. GitHub compare against old `305471b` confirmed the branch was unchanged before this run. Previous `CURRENT.md` was stale since 2026-10-17; treat this section as the newest checkpoint.

**Code changes (complete, not partial):**
- `976ff43`: `WindowSessionHistoryStore.lastSessionTargets(pid:)` and `recoverable(excluding:pid:limit:)` choose `lastCompleteOpen` when the running ChatGPT PID differs from persisted `appPID`; for the same PID, `previousSessionOpen` retains the existing previous-session contract. `hasPendingRestart(pid:)` uses the same selector.
- `f42c2ff`: all three production call sites in `ChatGPTTitleHelper.swift` supply the current PID (bulk restore and both sidecar recovery paths). Bulk checks live PID against tracked PID before selecting.
- `6b712a9`: four regression assertions for repeated restart PID 410→411→412, latest `New` vs older `A,B`, already-open suppression, and same-PID behavior; existing tests updated for explicit PID.
- `987fccb`: update the static `verify_native_sync.py` wiring assertions to the new PID-aware call sites. No changes to `NativeTitleSync` or Windows code. Draft PR #3 remains unmerged.

**MacMini2 authority and verified tests:**
- A clean detached worktree at `/Users/harshlad/_Project/titlehelper-restore-pid-6b712a90` checked out exact SHA `987fccb`; original dirty working directory was not modified.
- `bash macos/tests/run.sh` printed `PASS unchanged NativeTitleSync and event-driven wiring`, `PASS TitleWorkScheduler 14 assertions`, `PASS title history / session recovery 41 assertions`, `PASS native last-session + batch restore 73 assertions`, `PASS asynchronous restore verification policy 79 assertions`, and `BUILT artifacts/macos/ChatGPTTitleHelper`. Follow-up verified optimized binary (459088 bytes), clean worktree, `bash -n` PASS, no running compiler. The outer Dev MCP invocation timed out after ~60 seconds **despite successful test/build output**; verified via separate read-only reconciliation.
- Signed packaging executed **once** from that exact clean worktree with `macos/package-title-helper.sh`. Dev MCP returned `DELIVERY_UNKNOWN` after ~60s, but read-only reconciliation verified **actual installation**: signed `~/Applications/ChatGPTTitleOverlay.app` code signature PASS; installed executable mtime **2026-10-27 16:31:28 KST**, size 474640 bytes. Backup at `artifacts/macos/backups/titleoverlay-before-event.Ga8pezsK/ChatGPTTitleOverlay.app`. **Do not retry packaging without first reconciling state.**
- Original ChatGPT process remained running PID **27828**, not restarted or closed. The previously stopped helper was launched separately and now runs PID **78850**. New helper logs `ax-observer-created=true pid=27828`, `ax-subscriptions active=28`, `history-restart-pending pid=27828 saved=3`, and `refresh-success knownWindows=0`. Persistent JSON remains mode `0600`, `appPID=501`, `lastCompleteOpen=3`, `previousSessionOpen=5`. This proves the corrected **pending restart target is 3, not 5**, without opening chats.

**Still unverified / blockers:**
- **NO full Restore All E2E** yet. No Restore All click was attempted in this run. Do not infer no native windows from `knownWindows=0`; this counts recognized conversation titles, not raw AXWindows.
- Dedicated Mac screen capture via Dev MCP returned `INVALID_ARGUMENT`; `screencapture -x` reported `could not create image from display`. Signed TitleAXProbe returned `trusted=false` for Accessibility, and System Events AppleScript returned `-25211`. No TCC bypass attempted. Cannot honestly claim screenshots, body verification, or complete live AX window census.
- Dock Recent still fails for missing/duplicate titles; exact conversation UUID/URL is not yet persisted or proven as a non-destructive native new-window navigation route.
- The **16-second asynchronous title verification** is now deployed but not live E2E verified.

**Next autonomous step:** inspect the actual helper's native AXWindow count safely (prefer logging within its already AX-trusted process, without reading messages), restore screen-capture companion permission via supported owner-authorized route if possible, then test the Dock sidecar Restore All with a verified current-window census and screenshots. Preserve all existing user windows; never click arbitrary Dock items or overwrite a window. For Dock Recent-missing titles, research and test exact conversation ID/URL navigation on a *new blank* window only after proving no existing-window replacement. Update this file with each measured result. No Windows changes, no PR merge.


## 11. 2026-10-27 17:25 KST — live raw AX census now proves four native windows

**Reason for this checkpoint:** the prior `knownWindows=0` log counted *recognized conversation titles*, not native windows. A blind Restore All could duplicate or replace owner windows. We instrumented the AX-trusted existing helper to report **only raw AX window counts** on census transitions; no titles or messages are logged.

- GitHub feature commits `9b50538` (transition-only raw AX census), `042ac8a` (reset state on ChatGPT PID changes), `adb3380` (static test coverage). The exact tested source is `adb3380c4929e02d729eb5cbd8270e9e9a630f7f`.
- MacMini2 clean detached worktree `/Users/harshlad/_Project/titlehelper-ax-census-adb3380c`. `macos/tests/run.sh` output: unchanged NativeTitleSync PASS, scheduler 14, history 41, batch restore 73, asynchronous policy 79 assertions, optimized build generated (459344 bytes). Outer Dev call returned failure after ~59s but stdout contained all PASS lines and a subsequent read-only check confirmed clean source, built binary, no compiler.
- Signed deployment attempted **once**; Dev outer call returned failed after ~60s without worker result. **Read-only reconciliation confirmed installation succeeded**: `codesign --verify --deep --strict` PASS; installed helper executable mtime `2026-10-27 17:24:46 +0900`, 474896 bytes; new helper PID **38891**; ChatGPT PID **27828** preserved, no ChatGPT restart or window closure. Rollback: `/Users/harshlad/_Project/titlehelper-ax-census-adb3380c/artifacts/macos/backups/titleoverlay-before-event.fEOk28F6/ChatGPTTitleOverlay.app`.
- **Decisive live AX evidence** at `2026-10-27T08:24:48Z`: `ax-window-census available raw=4 recognized=0`, `history-restart-pending pid=27828 saved=3`. Thus **four native AXWindows are present** while none has a recognized conversation title. Earlier inference of zero native windows is disproven. This is not evidence of four distinct loaded conversations; titles, bodies, window roles, and duplicates remain unknown.
- Independent read-only CoreGraphics census before deployment found 14 ChatGPT-owned CGWindow records (11 layer-zero, including auxiliary/duplicate rectangles). These are *not* equivalent to native AXWindows; do not count them as restored conversations.
- No Restore All click, no ChatGPT Quit/relaunch, no user-window manipulation. Screen capture still not verified. Draft PR #3 remains unmerged; Windows and legacy NativeTitleSync unchanged.

**Next:** classify the four existing AXWindows within the already trusted helper by generic/non-generic/empty *native title categories only*, optionally minimized count, without printing actual titles. Before any Restore All action, verify which windows are existing conversations vs generic/auxiliary and ensure `freshOpenConversationTitles` preflight can identify them; it intentionally refuses multiple unidentified windows. Only then attempt non-destructive E2E. Investigate a durable conversation ID/URL navigation route separately, not by guessing URLs. Do not blindly rerun packaging after delivery-unknown; always reconcile signed installed binary and backup first.


## 12. 2026-10-27 17:31 KST — four AX windows are minimized; saved three do not match

**Highest-value finding:** We extended the trusted-helper count-only census rather than trying to click Restore All blindly. The installed helper reports:
```
2026-10-27T08:30:53Z ax-window-census available raw=4 recognized=0 nativeGeneric=1 nativeNamed=3 nativeEmpty=0 standard=4 minimized=4 matchedSaved=0/3 minimizedSaved=0
```
This means **four AXStandardWindows currently exist, all four are minimized**; three have non-generic native titles, one has generic `ChatGPT`. **None of the four native titles matches the three saved last-session targets exactly.** No raw title or message was logged. The zero recognized conversation count is explained at least in part by the existing collector deliberately skipping minimized windows; do not conflate with zero windows or data loss. Native titles may differ from web-area titles, so a zero native-title match does not by itself prove distinct conversations.

- GitHub commits `648596f` (native title category/minimized counts), `0872131` (static coverage), `8334648` (exact-match counts to saved last-session titles), `3893532` (test). Latest deployed source `38935327d8b8b0894617b666b939246530b3ad01`; clean detached worktree `/Users/harshlad/_Project/titlehelper-ax-saved-match-38935327`.
- MacMini2 `bash macos/tests/run.sh` **completed** at exact source SHA: NativeTitleSync unchanged PASS, scheduler 14, history 41, batch restore 73, asynchronous verification 79 assertions, optimized binary 459344 bytes. Windows code unchanged.
- Certificate packaging requested **once** for that SHA; outer MCP returned failed at ~60 seconds without worker status, but **read-only reconciliation confirmed successful deployment**: installed executable mtime `2026-10-27 17:30:52 +0900`, size 474896 bytes, `codesign --verify --deep --strict` PASS; new helper PID **46310**; original ChatGPT PID **27828** still running and never restarted. Rollback `/Users/harshlad/_Project/titlehelper-ax-saved-match-38935327/artifacts/macos/backups/titleoverlay-before-event.Gh4O4mVO/ChatGPTTitleOverlay.app`.
- Screen capture remains unavailable: native capture tool `INVALID_ARGUMENT`, `screencapture -x` returned `could not create image from display`. CoreGraphics confirms one active awake 1920x1080 display and console session; no TCC bypass attempted. CoreGraphics window names unavailable (`cgNamed=0`), so cannot match native windows from outside the AX-trusted helper.
- **No Restore All click or unminimize occurred**, and no existing ChatGPT windows were closed, raised, or overwritten. Draft PR #3 unmerged.

**Next:** first investigate why three minimized native titles differ from persisted `lastCompleteOpen` (the saved manifest PID is stale), using only aggregate exact-match counters against `previousSessionOpen` and `recentTitles`, plus native AX title vs AXWebArea-title semantics. The `freshOpenConversationTitles` preflight currently accepts at most one generic window; current census suggests one generic and three named windows, but this does **not** prove its AXWebArea lookup or native title identity succeeds. Do not duplicate already-open conversations. Once current native windows are safely identified, test the real Restore All callback with an authorized UI path and verify individual new windows by native AX count, title identity, and ideally body/screenshot; otherwise document the remaining blocker. Continue researching durable conversation IDs/URLs without guessing.


## 13. 2026-10-27 18:33 KST — minimized windows match neither saved nor recent titles

**Question:** Four AXStandardWindows exist and are all minimized; three have non-generic native titles. Do any correspond by *exact native AXTitle* to the saved last session (3), older previous session (5), or lifetime recent history (6)? A blind Restore All risks duplicates and therefore remains prohibited.

**Canonical macOS-only source changes:**
- `169accac3fa5f0a84e1345662928d513dad8b19d`: add aggregate `matchedPrevious` and `matchedRecent` counts alongside existing `matchedSaved` in the AX-trusted helper's initial census. No raw title, URL, message, or per-window fingerprint is logged; no restore behavior changed.
- `deafeb76eb5d4d342510eb0ce93dbffcb8d1eb35`: static test assertions for these new aggregate diagnostics. Only `macos/ChatGPTTitleHelper.swift` and `macos/tests/verify_native_sync.py` changed; legacy NativeTitleSync and Windows untouched.
- Clean detached MacMini2 worktree: `/Users/harshlad/_Project/titlehelper-ax-prior-match-deafeb76`, exact HEAD `deafeb76`. `bash macos/tests/run.sh` returned exit 0: unchanged NativeTitleSync PASS; scheduler 14 assertions, history 41, batch restore 73, async restore verification 79 assertions; optimized build generated.
- Signed packaging invoked **once** from exact clean worktree. Outer Dev MCP returned `DELIVERY_UNKNOWN` after ~60s, with reconciliation `request_in_progress`; **do not retry**. Read-only follow-up independently confirmed actual successful install at **2026-10-27 18:32:10 KST**, 474896-byte executable, `codesign --verify --deep --strict` PASS, helper PID **15742**, ChatGPT PID **27828** preserved. Rollback: `/Users/harshlad/_Project/titlehelper-ax-prior-match-deafeb76/artifacts/macos/backups/titleoverlay-before-event.mpA825HG/ChatGPTTitleOverlay.app`.

**Live AX result (2026-10-27T09:32:12Z):**
```
ax-window-census available raw=4 recognized=0 nativeGeneric=1 nativeNamed=3 nativeEmpty=0 standard=4 minimized=4 matchedSaved=0/3 minimizedSaved=0 matchedPrevious=0/5 matchedRecent=0/6
```
**Interpretation:** The three named minimized native AX window titles match **none** of the three saved last-session titles, five older previous-session titles, or six lifetime recent titles by exact string. This does **not** prove that those windows are different conversations: native window titles may differ from AXWebArea conversation titles, and minimized windows are deliberately excluded from the normal title collector. Do not use zero exact matches to authorize duplicate creation. The live log contained **zero** `history-bulk-request` events in the current helper log; Restore All was not invoked. The original four windows were not raised, closed, unminimized, or overwritten. No ChatGPT restart.

**Remaining blockers:** Dev native screen-capture call still returns `INVALID_ARGUMENT`, so no screenshot or conversation-body verification. Existing helper has Accessibility permission; separate Probe does not. No TCC bypass or injection. Durable conversation UUID/URL capture and safe native new-window navigation remain unproven. Draft PR #3 still unmerged.

**Next highest-value safe experiment:** instrument a **bounded, read-only, one-shot AX hierarchy/title-availability diagnostic inside the already trusted helper** for minimized windows, reporting only aggregate counts and exact-match counts for AXWebArea titles vs saved/previous/recent. Bound traversal/time to avoid UI stalls; never log titles/messages. First investigate whether minimized windows expose AXWebArea at all; if unavailable, do not automatically unminimize owner windows. Separately inspect screen-capture companion configuration via supported permission checks. Only attempt Restore All after the already-open conversation identity can be established well enough to prevent duplicates. Continue using exact GitHub HEAD, detached Mac worktree, signed backup, read-only post-deployment reconciliation, and CURRENT.md checkpoints.
