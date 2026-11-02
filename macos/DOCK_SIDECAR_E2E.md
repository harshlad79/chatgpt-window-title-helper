# Dock context-menu sidecar — implementation and Mac E2E

Date: 2026-10-16 KST. This feature is an independent overlay, NOT an attempt to modify a ChatGPT AXWindow title or Dock's owned menu items. The existing native writer remains disabled.

## User problem

Dock right-click on the ChatGPT icon shows multiple native window items all titled "ChatGPT". The user needs to recognize which conversation each actual window represents, without changing the stored ChatGPT conversation title or patching the signed ChatGPT app.

## Read-only detection evidence

A stable-signed, Accessibility-authorized TitleAXProbe found the ChatGPT Dock icon:
- AXRole = AXDockItem; AXSubrole = AXApplicationDockItem.
- AXShowMenu is a supported action on that **specific** icon.
- Owner-authorized AXShowMenu returned status 0.
- Open Dock menu appears as AXMenu beneath this DockItem. Example position (864,524), size (276 x 464) in AX top-left screen coordinates.
- Two actual AXMenuItem entries titled "ChatGPT" were observed (their positions/sizes can be read separately).
- No Dock or ChatGPT title was written.

## Implementation — GitHub 1f422ecf877836799ee04b8b5e1961183d26969d

macos/DockMenuSidecar.swift:
- Accesses only the Dock app's AX hierarchy. Resolves the uniquely titled ChatGPT application AXDockItem.
- Polls the item's **direct children** every 300 ms while idle. Rediscovery of the icon is bounded (5s) and refreshed on Dock PID change.
- Only shows if the actual Dock AXMenu is a child of the ChatGPT icon and contains a ChatGPT AXMenuItem.
- Reads menu rectangle. Places separate, self-owned, nonactivating NSPanel to left (or right when space requires), with a 10pt gap and no overlap; refuses to show if neither side has room.
- Shows a standalone list titled "ChatGPT 대화 창". Each button has the title and AXWindow identity of the associated conversation. Clicking attempts to raise that exact AXWindow. It **does not guess** how ambiguous native Dock menu items correspond to windows.
- Maximum ten listed visible cached AX windows; full window search is NOT performed every 300ms. Existing efficient event+fallback title cache supplies entries.
- Hides the sidecar when the Dock menu is no longer observable. Never intercepts mouse activity over the original Dock menu.
- Existing original NativeTitleSync is preserved byte-for-byte; no SIGUSR1 or inspector used.

macos/ChatGPTTitleHelper.swift:
- Starts the sidecar on launch and stops it when TitleHelper exits.
- Tracks AXWindow object identity in the ordinary 2-second refresh, and feeds cached conversation titles to the sidecar.
- On row click, activates ChatGPT and invokes AXRaise on that exact window.
- Existing on-window overlay remains untouched.

## Verified runtime

The canonical commit 1f422ec was checked out in a **clean** separate Git worktree and rebuilt:
- 26 TitleWorkScheduler/TitleRevisionRetryPlan tests PASS.
- NativeTitleSync exact source comparison PASS.
- Swift application build PASS; Git worktree clean.
- TheCompany stable certificate-signed bundle installed and verified under the existing app identity local.chatgpt.titleoverlay.
- ChatGPT PID 80584 remained running without restart/patch/signal. New helper PID 80795 ran with working AX observer.
- In actual open Dock ChatGPT menu, the sidecar was shown. Main helper log: dock-sidecar-visible rows=1 at first title read; followed immediately by a second title read.
- AX census of running helper showed TWO sidecar NSButtons with correct, distinct title fingerprints len18:shacd4ee6ac07d9 and len13:sha8a2fb676a6b4.
- CGWindowList confirmed visible panel owned by "ChatGPT Title Overlay", bounds X=534 Y=524 width=320 height=118; Dock menu X=864 Y=524 width=276 height=464, proving 10px horizontal separation.
- Original existing on-window overlay was still visible separately.
- ChatGPT and helper remained alive.

## Pending manual E2E

**Menu close-to-hide is not yet verified.** Sending an Escape event addressed to the Dock PID through CGEvent.postToPid was attempted, but the Dock menu remained open. System Events keystroke was then explicitly **denied** with error 1002 ("osascript not allowed to send keystrokes"), so do not bypass that permission by an alternative injection route. The owner must dismiss the open Dock menu normally by clicking outside, after which logs should show dock-sidecar-hidden.

**Click-to-raise is not yet verified through a real user selection.** Once the menu is open, selecting a sidecar title should activate the corresponding AXWindow. Verify that exact window is frontmost rather than inferring success from the action call.

## Rollback

The installed helper has a preserved backup:
`/Users/harshlad/_Project/chatgpt-dock-sidecar-verified-1f422ecf877836799ee04b8b5e1961183d26969d/artifacts/macos/backups/titleoverlay-before-event.yhaelpms/ChatGPTTitleOverlay.app`

Original ChatGPT application is untouched, feature branch remains Draft PR #3, unmerged. No Windows source changed.
