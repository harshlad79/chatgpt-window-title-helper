# macOS Dock sidecar — restore all windows from last session

Date: 2026-10-17 KST. Verified feature-branch source SHA: `1db37e7cf203902be4ceb670a4d70109ddb886e7`.
This is an opt-in bulk recovery feature for **both clean Quit and unexpected app termination**, not a general chronological list of every chat. The Apple-signed ChatGPT binary was not modified or restarted. Preserve original NativeTitleSync byte-for-byte and its default compile-time inspector safety fence.

## Background-free navigation investigation

The official ChatGPT/Codex desktop deep-link reference documents `codex://threads/<thread-id>` for **local** threads only, requiring an actual technical thread ID. It does not document reconstructing the required conversation-specific IDs from the Dock Recent menu or the sidebar. The earlier live Mac AX investigation found:
- Sidebar conversation AXButton AXURL and AXDOMIdentifier empty, including ancestors.
- Dock Recent > second More: AXMenuItems support AXPress but all lacked usable per-chat AXURL/unique AXIdentifier.
- Read-only AppleScript window request against the installed ChatGPT timed out (-1712).
Therefore there is currently no **verified** no-visible-menu route for these specifically identified previous ChatGPT conversations. Do not pretend `codex://threads/<title>` is valid. Preserve the verified native AX menu sequence as fallback. Reference: https://learn.chatgpt.com/docs/reference/commands#deep-links

## Native E2E foundation previously confirmed

- `파일 → 새 창` AXPress returned success 0 and increased ChatGPT AXWindows 1 → 2.
- Exact unique `Dock → Recent → second More → chat title` AXPress returned success 0, changed only the newly opened generic ChatGPT window to the target conversation title, and preserved the prior window and its distinct title. ChatGPT AXWindows remained 2.
- Owner independently confirmed that a Dock Recent-selected conversation displayed its content correctly. The exact combined separate-new-window content rendering was not independently owner-verified.
- Dock menus visibly open while AXShowMenu is used and UI may temporarily take focus. No background-only restore mechanism claimed.

## New restore-all implementation

`macos/WindowSessionHistoryStore.swift`: atomic Codable JSON under `~/Library/Application Support/ChatGPTTitleOverlay/window-session-history.json`.
- `lastCompleteOpen` persists **only a complete AX title census**; partial/unavailable AX scans and zero-window transients do not erase the last set.
- On ChatGPT PID change, carries the former `lastCompleteOpen` into `previousSessionOpen`, and uses that as the last-session restore target.
- For normal Quit, shrink candidates are held for 12 seconds. Closing native windows one at a time during Quit does not immediately replace the saved last complete set; a stable smaller set after the grace period is eventually accepted as an intentional close.
- No raw chat messages or links are stored, only titles. JSON is now written with 0600 and older 0644 JSON migrated on load.
- Last-session target set is separate from the lifetime `recentTitles` history; **bulk restore never opens all historically viewed chats**.

`macos/DockMenuSidecar.swift`:
- Existing upper section: AXWindow-identity-based currently open windows; pressing a title raises that exact window.
- Lower section: missing titles from the last session (up to 8 shown as selectable rows).
- A **"마지막 창 모두 복원 (N)"** button at the bottom launches restoration of the entire recoverable last-window set, potentially beyond the eight individually displayed titles. Already open titles excluded.
- Dock menu recognition is tied to the uniquely located ChatGPT application AXDockItem and its AXMenu even when **zero native ChatGPT windows** exist.
- A partial AX census at startup suppresses the historical/missing section. Live log from release demonstrated `dock-sidecar-visible rows=1 history=0` before title caching completed, where prior release incorrectly showed two missing titles.

`macos/WindowSessionRestoreQueue.swift` and `macos/RestoreProgressPanel.swift`:
- Explicit click starts an **ordered, single-flight** queue. Per title: `파일 → 새 창`, verify window identity, Dock Recent exact unique AXPress, verify new window native caption and preservation of old windows.
- Skips titles already open, coalesces identical titles (not a unique conversation ID), rejects overlapping queue starts.
- Never guesses among multiple Dock Recent items with identical names. Unavailable or ambiguous titles are reported as failures; subsequent distinct targets may still be attempted.
- Progress NSPanel remains visible while Dock menu is dismissed. Shows completed / planned counts, failures, and user-visible current title; cancel stops **after** the in-flight native operation; processing yields between entries. On completion hides after a brief delay.
- Avoids process hooks, unsafe Electron inspector, SIGUSR1, ChatGPT binary edits, AppleEvent keystroke injection or invisible unverified deep links.
- A failure after creating an empty new window does **not** automatically close any user window.

`macos/ChatGPTTitleHelper.swift`: gates BOTH single-row and bulk restore actions on a full AXWindow title census and a live matching ChatGPT PID. Does not offer recovery buttons for falsely missing windows while title cache warms up. Refreshes sidebar and JSON state after actions.

## Test and deployment evidence

- A clean GitHub checkout of exact SHA `1db37e7` had all modified Swift sources **byte-for-byte identical** to the tested worktree and zero masked placeholders.
- Original NativeTitleSync byte identity test PASS.
- 66 Swift assertions PASS: scheduling, bounded AX title retry, JSON reload, crash PID switch, normal Quit sequential window shrink preservation, stable deliberate close after >12s, 0600 chmod on new write and migration of legacy existing JSON, queue ordering, already-open/duplicate filtering, cancellation and overlapping-start rejection.
- Full optimized Swift build PASS from canonical exact SHA, resulting unsigned binary 453,264 bytes.
- Signed deployment to existing `~/Applications/ChatGPTTitleOverlay.app` completed; source binary timestamp 2026-10-17T04:05:35+0900, installed signed executable timestamp 2026-10-17T04:06:55+0900, size 468,880 bytes, `codesign --verify --deep --strict` PASS.
- Installed helper PID **64962** and original OpenAI ChatGPT PID **35112** both remained alive.
- Rollback copy preserved: `/Users/harshlad/_Project/titlehelper-final-gated-1db37e7cf203902be4ceb670a4d70109ddb886e7/artifacts/macos/backups/titleoverlay-before-event.diT1la9t`.
- Existing production history schema 1: current complete 3 names, previous-session 0 (no actual ChatGPT restart in this test), recent title history 4, mode **0600**.
- Notifier and task records through TheCompany-Dev, no main merge, PR #3 remains Draft.
- **Important remote tool failure receipt:** The Dev MCP packaging call returned `failed` after **60,187ms** with path `control-n150/thecompany-chatgpt-mcp → control.invoke → macos-main` and did not provide an exit code or error reason. A subsequent **read-only** on-machine reconciliation verified the actual signed installation, backup, helper restart, target ChatGPT PID preservation, history migration and partial-cache gating. No blind retry / duplicate install.

## Remaining E2E validation

The test did **not** intentionally terminate the owner's ChatGPT app or close the owner's existing windows. Thus **full native Quit → relaunch → one-click multiwindow restore** has not yet been observed end to end in the installed release. The integrated bulk UI callback was verified by compile/tests, not clicked with an actual missing-window last-session manifest.

The owner should perform a routine **normal ChatGPT Quit**, then relaunch, open Dock sidecar and click `마지막 창 모두 복원`. Observe correct number of separately opened native windows and original conversation bodies. The title-based method cannot safely resolve two distinct chats having equal titles or titles no longer present in Dock Recent. Those cases remain incomplete and must not be reported as restored.

No Windows source, ChatGPT official binary or original NativeTitleSync altered.
