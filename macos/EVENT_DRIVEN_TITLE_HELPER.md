# Mac TitleHelper: Windows-style event-driven title detection

Status: **implemented and compiled on macos-main; native live app
deployment and Dock-title E2E validation still pending** (2026-10-15).
Branch: feat/macos-adaptive-title-helper / Draft PR #3.
Never conflate compilation with on-screen runtime success.

## Scope and non-goals

The original working NativeTitleSync (Electron/Inspector via
BrowserWindow.setTitle) must remain byte-for-byte unchanged.
It is preserved in macos/legacy/ChatGPTTitleOverlay.swift.
The corresponding block in the new macos/ChatGPTTitleHelper.swift must
also match the legacy original; verify with
python3 macos/tests/verify_native_sync.py.

Do not edit the ChatGPT conversation title or bring its window to the
foreground for routine detection. The probe's guarded title-editing
experiment was independent of the user's actual goal: read the
conversation title and let the existing native writer put it into the
window/Dock title. Do not add Inspector activation code; the existing
NativeTitleSync is preserved as supplied, without behavior changes.

Do not modify the currently installed ad-hoc signed legacy
~/Applications/ChatGPTTitleOverlay.app automatically, change its
permissions, or launch a second overlapping helper without owner approval.

## Windows source of truth

The repository's Windows master at
0b7e05e06bcb939d2b4e72f1b8e185dde2b7dd35 uses:
- Automation/TitleButtonEventMonitor.cs: subscribe to the actual title
  button's UIA Name property, forward the changed title as an event.
- Windows/WindowNameChangeMonitor.cs: OS window identity, foreground,
  name and move/size events without a flood of irrelevant UIA children.
- Windows/AdaptiveTitleWorkQueue.cs: deduplicated priority requests;
  immediate event > active window > background. Single worker, single
  expired window per discovery tick. On success retry after 20 seconds;
  after failure use bounded exponential backoff.
- ApplicationContext.cs: a 2-second cheap window discovery timer,
  dedicated title-processing worker, and a separate native caption
  reapply path. It does NOT traverse every window's UIA tree each tick.

## Equivalent Mac source

- macos/MacAXTitleObserver.swift — AXObserver with application
  window-created, focused/main-window changes, per-window geometry/title,
  and title-bearing AXWebArea and title-matching AXButton title/value
  notifications. The callback enqueues the window key only; NO
  accessibility tree access in the callback.
- macos/TitleWorkScheduler.swift — purely deterministic priority and
  due logic, no AX APIs. Immediate/active/background, coalescing,
  deterministic FIFO/tie-breaking, 20s overdue fallback, bounded
  exponential backoff and removal of missing windows.
- macos/ChatGPTTitleHelper.swift — derived from the original, unchanged
  NativeTitleSync. Poll timer reduced from a 0.5-second full scan to
  2-second cheap AXWindows discovery. Newly discovered/focused/event
  windows enter the priority queue. Queued work reads at most one
  window AX subtree at a time. AXWebArea.Title is authoritative for
  title text regardless of length. A unique, matching AXButton.Title
  is subscribed to as the Mac analogue of Windows title-button events.
  The cached title list goes to the ORIGINAL NativeTitleSync.sync.
- macos/main.swift — standard Swift multi-source entry point.
- macos/build-title-helper.sh — build only into ignored
  artifacts/macos/ChatGPTTitleHelper; does not sign/install/launch.
- macos/tests/run.sh — native-source build, exact NativeTitleSync block
  equivalence assertion, and deterministic scheduler unit tests.

## Intended runtime behavior

1. Observe a running application with bundle ID com.openai.codex.
2. On startup or process replacement, reset AX observer and cache.
3. Every two seconds enumerate native AXWindows cheaply; identify
   added/removed/minimized windows, their IDs, and the focused window.
4. Title work runs for at most ONE window per refresh. A title event
   is immediate, a newly focused window is active, and at most one
   overdue cached window is background-priority.
5. The title element search is AX role-based, cycle-checked and capped
   at 1600 nodes. It tries AXChildren and falls back to visible/contents
   for inaccessible Chromium subtrees. One-character titles are valid.
6. The AX callback posts a debounced (80 ms) request; extra queued work
   is processed 140 ms later, one window at a time. No generic group
   event subscriptions, so the 400-notification saturation from early
   probes is avoided.
7. Window geometry events re-queue the affected window so the overlay
   follows it. Changed titles reset the existing NativeTitleSync's
   throttle to allow prompt delivery. Slow discovery retains the
   original native title-reapply behavior without repeated full AX
   traversal.
8. Unavailable AX values get a retry at 2, 4, 8, 16, up to 30 seconds.
   Inactive/minimized windows are not scheduled until visible.
9. Subscriptions follow the current window and title element identities.
   Old remote elements may refuse unsubscription; local references
   are dropped to avoid long-lived stale subscriptions.

## Validation and deployment gate

On macos-main, ./macos/tests/run.sh completed:
- Unmodified NativeTitleSync implementation match: PASS.
- TitleWorkScheduler: 14 independent assertions PASS.
- Full AppKit/ApplicationServices/QuartzCore Swift compilation: PASS.
- Original installed ChatGPTTitleOverlay.app: NOT replaced.
- Windows source: NOT modified.
- macOS AX event delivery in this NEW integrated helper: NOT YET
  observed live (TitleProbe had already observed events).
- End-to-end Dock/native window title for this NEW helper: NOT YET
  observed live. Must not report this as verified.

Before deployment: verify the actual target application bundle and
existing permission principal. The currently installed legacy
ChatGPTTitleOverlay.app uses ad-hoc signing; switching its binary to
the existing TheCompany 2036 certificate can require ONE new TCC
Accessibility approval. Use that stable identity for subsequent updates,
verify DR/Bundle ID and user permission retention, preserve a rollback
bundle, and do not build with the old ad-hoc legacy/build.sh script
for persistent installations.

Test plan:
- User-authorized test installation and accessibility grant, if needed.
- Observe title-button AXTitleChanged and AXWebArea.Title without
  requiring foreground focus or editing conversation text.
- Rename one conversation through the user's own ChatGPT UI, verify
  update latency and current Dock window-list title by actual GUI view.
- Test 1-character, long, Korean/English titles, many open windows,
  minimizing/unminimizing, focused-window changes, process restart.
- Verify native Dock title writer and rollback still work WITHOUT
  altering NativeTitleSync, ensure no unexpected Inspector changes.
- Measure CPU time and event-vs-fallback refresh counts; ensure each
  2-second discovery tick does not traverse all AX trees.
