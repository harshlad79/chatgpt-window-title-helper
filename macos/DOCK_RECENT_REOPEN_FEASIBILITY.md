# ChatGPT Dock Recent → More: AX action reuse feasibility (2026-10-16)

## Owner hypothesis and goal

The ChatGPT Dock right-click menu has a **Recent → More** submenu containing many prior conversations. Rather than reverse-engineer chat IDs from the left sidebar, leverage this already working list to recover known previously-open conversations after the official app exits/crashes. Keep the existing independent native window-title AX observer, safe Dock sidecar and unchanged NativeTitleSync. Do not patch/inspect the official app's process memory.

## Live Mac evidence

Machine: macos-main; official ChatGPT PID 35112, stable-signed Accessibility-approved TitleAXProbe. Read-only interrogation preceded one explicit, user-requested E2E launch of a known Dock Recent entry.

1. ChatGPT Dock application AXDockItem supports AXShowMenu (status **0**).
2. The native menu has **two "More" items**. The SECOND is the one following the Recent section. The second More's AXChildren contains one **AXMenu**.
3. That AXMenu has **77 AXMenuItem** children in the current runtime. All 77 expose distinct/possibly duplicate human-visible titles. AXMenuItem actions are **AXCancel, AXPress, AXPick**.
4. None exposes AXURL. All 77 advertise AXIdentifier, but the value is the SAME 7-character label fingerprint across all 77; this is a generic identifier, **not** a unique chat ID. They also expose AXMenuItemPrimaryUIElement, with one shared AX element type; no usable per-item URL was found in these AX properties.
5. Duplicate titles already occur in this real list (e.g., two adjacent positions with equal title fingerprint). Therefore finding by title alone is only safe if an exact title has one match at action time. **Never automatically choose the first among duplicates.**
6. Under an isolated, explicit E2E test, we selected one screenshot-grounded recent conversation (17-character title, hash `sha94056e7278e0`) and verified exactly **one** corresponding AXMenuItem among the 77. Calling AXPress on that item returned success **0**. No messages were sent and no conversation titles were edited.
7. Before selection, the ChatGPT app's AXWindows count was 1. Immediately after, it was still 1. The selected item was reflected in the app's native AXWindow.AXTitle (`len17:sha94056e7278e0`), precisely equal to the selected recent title. This is positive evidence that Dock action reached the app and caused it to open/navigate to the selected conversation window.
8. HOWEVER this test's ChatGPT window exposed no AXWebArea both immediately before and after the selection; a further read-only scan 1 minute later still exposed only ~23 AX nodes. Therefore **actual chat content completion is not verified**, and no **new native window** was demonstrated. The ChatGPT app continued running. Preserve this caveat and do not claim full crash-recovery E2E yet.
9. The installed production TitleHelper stayed running, without SIGUSR1 calls or native writer activation. This investigation modified only the stable-signed scratch TitleAXProbe and created this documentation; official ChatGPT binary was untouched.

## Consequences for implementation

This is a more promising path for **short-term reopen by known recent title** than extracting nonexistent conversation links from the sidebar AXButton properties.

Proposed workflow:
- Independently persist locally a history of actually open ChatGPT windows (title, first/last observed, last active, last session membership, and actual stable URL/ID **if ever available**), using atomic writes; do not treat AXWindow hash or ChromeAXNodeId as persistent IDs.
- For "Restore from Recent", on explicit user click, query the Dock's *current* Recent → More submenu and find exact-title AXMenuItems. Press only when there is exactly one match and AXPress is supported.
- Resolve the result only after checking the target app's actual AXWindow/AXWebArea title and preferably chat content loading. Distinguish successful **navigation into existing window** from verified creation of a **new** ChatGPT window.
- If title duplicated/missing, do not press; show ambiguity or unavailable state. New-window restore/entire previous-session restore are still separate unverified capabilities.
- Limit Dock menu scanning to an explicit restore operation or low-frequency background observation; opening Dock context menus unprompted during the owner's workflow steals focus and is undesirable.
- Research official ChatGPT `Copy chat deep link` as a potentially durable alternative. The tested AXMenuItem exposes no URL directly.

This is experimental evidence, not proof that macOS Dock Recent retains the same 77-item list across future ChatGPT restarts, updates or app crashes; that persistence remains to be confirmed.

## Safety

No automatic bulk launch, no implicit duplicate resolution, no GUI injection, no process hooks, no TCC escalation. Preserve production NativeTitleSync source and compiled-out unsafe Inspector writer.

Relevant earlier record: `macos/SIDEBAR_CONVERSATION_LINK_AX_INVESTIGATION.md`.


## 2026-10-16 — Owner-confirmed end-to-end body rendering

After the guarded AXPress of the **unique** screenshot-grounded Dock Recent item “터미널 tmux 연결 구조 파악”, the owner explicitly confirmed: **the selected conversation opened normally, including its content**. This resolves the previous uncertainty about end-user chat rendering in that specific test; the AXWebArea census was incomplete despite the visible application having loaded the conversation.

Verified end-to-end for **opening one chosen conversation from Dock Recent**:
- exact unique menu-title match among 77 recent items
- AXPress succeeded
- ChatGPT native AXWindow title matched the requested conversation
- owner observed the correct conversation fully opened

Still **not** verified: creating a *separate new native window* for each restored chat, opening multiple previous-session windows, whether Dock Recent persists across a crash, how long it retains entries, or safely resolving identically titled conversations. Do not declare whole-session restoration implemented. A crash-resistant history database and user-triggered restore UI are still design/implementation work.

Implementation direction: keep a local atomic session manifest of known open window titles plus timestamp/order; use Dock Recent lookup on demand, only if there is exactly one matching title. Treat that as a guarded best-effort recovery route, not a globally unique identity or universal history. Evaluate the native “open in new window” path separately before supporting multiwindow restoration.
