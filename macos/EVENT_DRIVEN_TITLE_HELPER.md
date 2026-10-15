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
   overdue cached window is background-priority, requested ONLY by the
   two-second discovery timer (not an event burst or backlog drain).
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

## Deployment execution status — 2026-10-15 16:03 KST

The deployment operator completed the preflight on macos-main at feature
HEAD bc8cac700b42add2ca756b82368b8ad89fb834c9:
- Built ChatGPTTitleHelper successfully.
- Passed unchanged NativeTitleSync comparison.
- Passed all 14 scheduler assertions.
- Observed the owner-installed original
  ~/Applications/ChatGPTTitleOverlay.app: Bundle ID local.chatgpt.titleoverlay,
  current signature ad-hoc, valid; not running.
- Found TheCompany 2036 certificate in login keychain.
- User defaults: overlayEnabled=1, nativeTitleEnabled=1.
- Generated the explicit opt-in script macos/package-title-helper.sh to
  reuse the existing bundle path, backup the original, replace only its
  executable with the event-driven build, sign once with the stable
  TheCompany identity, verify DR and retain rollback copy.
- The actual remote deployment execution was **blocked by the assistant
  tool's safety check** before installation. Do not claim it ran, and
  do not bypass the block using alternative remote execution paths.
- Read-only postcheck confirmed the old installed app is still ad-hoc,
  and no new titleoverlay-before-event backup exists. No new app was
  installed or launched, and Dock E2E remains unverified.

The installation script is left as a reviewable, opt-in deployment
artifact. It does not run as part of build or tests. If the owner
chooses to run a reviewed installer on their Mac, pause for any needed
Keychain approval and Accessibility authorization. Never reset TCC
or modify the working NativeTitleSync to force installation.

## Live owner-authorized test: Accessibility approval, 2026-10-15 evening

- The approved signed app (Bundle ID local.chatgpt.titleoverlay; TheCompany
  certificate EBC7B73928C50D22D965AFE909AB5CBD519FB851) became
  AXIsProcessTrusted=true in its existing process, without re-signing.
- It registered 62 AX subscriptions against original ChatGPT PID 37140 and
  successfully detected one titled conversation window.
- The ChatGPT process then exited. A new process PID 66399 launched, showing
  at most shallow native AXWindow groups and no AXWebArea while inactive.
  The observer still received AXMoved events, but there were no title
  elements to subscribe to. The ChatGPT process later exited too.
- The *unchanged* legacy NativeTitleSync attempts to contact localhost
  9229 and, if no inspector is present, sends SIGUSR1 to the ChatGPT PID.
  Port 9229 was not listening in these checks. Exits happened while
  this writer was enabled, but precise termination cause / signal is
  NOT established. Do not claim SIGUSR1 was proved to kill ChatGPT.
- To avoid repeating a possibly destructive action, the new TitleHelper
  process was **stopped**. The installed code-signed bundle and ad-hoc
  rollback backups were retained without other changes.
- ChatGPT was launched independently in the background, without TitleHelper,
  and survived >20 s. AX windows were still shallow when ChatGPT was
  inactive. After explicitly activating ChatGPT once, signed TitleProbe
  detected one AXWebArea, but its title was the generic "ChatGPT"
  (length 7), not a named conversation.
- Actual AX conversation-title change notifications and Dock window-list
  name update were therefore NOT validated. User needs to open an actual
  named conversation and confirm a non-generic title, before further E2E
  testing. Do not automatically rename the conversation.
- Runtime instrumentation is kept in TitleHelperDiagnostics.swift and
  derived source; no raw conversation bodies/titles in diagnostic file.
  The diagnostic callback now differentiates "inspector-pending",
  "no-title" and "sync-returned-count" rather than calling every
  "Dock: ..." message successful.

**Before relaunching the installed native writer**, examine the
inspector-start path's safety on ChatGPT 26.1007.71326. Do not
automatically replay the previous SIGUSR1 path while its compatibility
is unresolved; the old class remains verbatim, per owner direction.

## Safeguarded passive AX rollout — 2026-10-15 (owner-approved)

The root-cause investigation of earlier ChatGPT exits found macOS launchd:
- 21:46:47 KST: PID 37140 exited due to SIGUSR1 sent by
  ChatGPTTitleOverlay[60108].
- 21:52:39 KST: PID 66399 exited due to SIGUSR1 sent by
  ChatGPTTitleOverlay[60108].

The legacy NativeTitleSync class remains byte-for-byte identical to the
old known-working source, including its unsafe SIGUSR1 fallback. The
current **default build** is a fail-closed passive-only development stage:
- Every caller of nativeSync.sync and nativeSync.restore (refresh, menu,
  shutdown) is compiled out without the TITLEHELPER_NATIVE_WRITER_VERIFIED
  Swift conditional flag. The shipping build script never defines it.
- The UI displays Dock: 안전 중지 (Inspector 미검증) rather than
  claiming a successful Dock title update.
- Do NOT define the flag until the native writer has a verified
  no-signal Inspector transport. A simple preflight probe of 9229 is
  insufficient because the inspector could disconnect after checking.
- AXObserver and one-window priority queue continue to operate.
  TitleHelperDiagnostics.fingerprint records only title length and 6-byte
  SHA-256 prefix, never title text or conversation content.
- Original installer rollback bundles are preserved under ignored artifacts.

Validation:
- NativeTitleSync verbatim equality test: PASS.
- Structural Swift default-branch test: NO reachable sync/restore: PASS.
- Scheduler + one-character Korean and English title fingerprints:
  18 assertions PASS.
- Swift full build PASS.

Owner-approved Mac runtime:
- One remote package request returned MCP failed after 60167 ms with
  no worker exit code, but subsequent read-only reconciliation proved
  the deployment HAD finished: updated signed executable and new backup.
  Do not rerun installers blindly after a transport-level uncertainty.
- The app was started via LaunchServices under the same long-lived
  TheCompany cert and existing bundle ID. It launched with AX trust.
- With ChatGPT initially inactive no AX windows were exposed.
  Activating ChatGPT once (no conversation rename or content edits)
  caused one conversation title to be read in 47ms:
  ax-title-read source=discovery-or-due ok=true durationMs=47
  fingerprint=len42:shaee1876263c82.
  AX subscriptions active=12, ChatGPT and TitleHelper processes alive.
- The runtime emitted zero native-sync-result records, by design.
- A real title-change notification is NOT YET validated against a
  user-initiated title change in this stage. The Dock native title
  writer is NOT YET enabled. Do not report Dock E2E as passed.
- Prior to enabling Dock writing, validate a replacement transport
  that never signals ChatGPT and checks Inspector ownership.
