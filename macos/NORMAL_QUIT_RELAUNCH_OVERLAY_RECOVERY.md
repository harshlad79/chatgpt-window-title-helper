# Regression: no Dock sidecar after normal ChatGPT Quit and relaunch

Date 2026-10-17 KST; macos-main. User reported that after a *normal* ChatGPT Quit and subsequent relaunch, neither the old overlay nor last-window restore sidecar appeared.

## Actual on-device root cause

- OpenAI ChatGPT original process switched **PID 35112 → 70502** across the owner's Quit/relaunch.
- The TitleHelper stayed running (PID **64962**) with signed bundle verified and AX observer subscribed to new PID.
- TitleHelper log repeatedly reported `refresh-success knownWindows=0`, while its `readConversationWindow` attempts yielded `ok=false`, because the relaunched ChatGPT exposed a generic native window with no loaded conversation AXWebArea title.
- Independently signed, AX-trusted TitleAXProbe saw **one AXWindow** with generic title "ChatGPT", confirming this is not proof there are no native windows, merely no recognized loaded *conversation*.
- The local atomic history file `~/Library/Application Support/ChatGPTTitleOverlay/window-session-history.json` was intact (mode 0600), appPID=35112, **lastCompleteOpen=3**, previousSessionOpen=0. No data loss.
- Existing `ChatGPTTitleHelper.refresh` treated **any** incomplete title census as an empty recoverable list by calling `dockSidecar.updateHistory([])`. In addition, the handler for 'Restore All' unconditionally required a complete AX title cache, even immediately after process restart. Since sidecar had zero current entries **and** history was forcibly empty, its display gate hid the entire panel. This made restoration UI unreachable at the exact moment it was needed.
- Purely activating an already-running ChatGPT with `open -a /Applications/ChatGPT.app` did not resolve the incomplete AX chat-title visibility.

## Corrective patch

Canonical GitHub feature commit `e7f0e5a5a65044e6ca32d7b01d6a65c5617810c0`:

- If the current ChatGPT PID differs from persisted `appPID` and its AX title cache is still incomplete, **show saved prior session titles** instead of clearing the Dock sidecar. It **does not** infer any windows to open automatically.
- Added `WindowSessionHistoryStore.hasPendingRestart(pid:)` to make exact restart detection testable, and preserve the existing complete-census-only JSON write fence.
- The individual/bulk restore callbacks now have a **fresh foreground preflight**: activate the existing ChatGPT app (without relaunch), wait ~850ms, rebuild a new process-specific AX app handle and query `AXWindows`; recover already-open conversation titles from cached/actual AXWebArea/native title when possible. Tolerates a single generic initial "ChatGPT" window; refuses multiple unidentified windows or AX failures instead of silently clicking or duplicating known chats. Then starts the existing guarded `File → New Window → Dock Recent unique-title AXPress` restore loop.
- Reports errors to an NSAlert rather than silently ignoring a failed AX-census guard. Cancel/progress and session writer remain unchanged. Original `NativeTitleSync` source remains byte-identical, SIGUSR1/inspector disabled.

## Verification

- From exact clean canonical feature SHA, changed sources were byte-compared with the locally tested source; no masked placeholders.
- Swift regression test assertions **69 PASS** (was 66), including same-PID no false history and different-PID pending restoration visibility.
- Full macOS optimized Swift build success; signed installed bundle verified.
- Dev remote packaging request returned `failed` after **60,162ms** with only `mcp_path=control-n150/thecompany-chatgpt-mcp → control.invoke → macos-main`, no exit-code/error. Read-only runtime reconciliation **verified deployment completed**: new helper PID **94099**, original ChatGPT PID **70502** unchanged, signature verification success, preserved rollback backup `.../titlehelper-restart-verified-e7f0e5a5a65044e6ca32d7b01d6a65c5617810c0/artifacts/macos/backups/titleoverlay-before-event.9XIfHTsP`.
- New helper log `history-restart-pending pid=70502 saved=3`.
- Exact authorized ChatGPT Dock icon `AXShowMenu` returned status0; real native Dock AXMenu detected, and title sidecar showed: `dock-sidecar-visible rows=0 history=3`.
- Signed AX-trusted test enumerated **one sidecar NSPanel and four buttons** (three distinct stored chat titles + the Restore All button). This is actual Mac GUI/AX E2E evidence, not a model preview.
- Sidecar's ordinary on-window conversation-title overlay is expected to be absent until a real loaded chat AXWebArea exists; that is separate from the repaired Dock recovery panel.

## Integrated Restore All click still pending

An attempt to automate the restored sidecar button from a separate signed Probe failed to find the button, because launching/reinvoking the Probe itself dismissed the Dock context menu before probing the sidecar. A revised single-process AXShowMenu → sidecar AXPress attempt also returned `AXShowMenu=0` but the native menu did not remain open in the background Probe-driven run; `BULK_UI_E2E windows=0; blocked=buttonCount=0`. **No bulk button action ran and no additional chats were opened by this test**.

Owner should open the ChatGPT Dock menu **manually**, see three saved prior windows at the bottom, and click `마지막 창 모두 복원 (3)`. The current callback then performs user-triggered foreground AX validation and guarded sequential new-native-window + Dock Recent reopens. Observe progress and preserve any failure log. Do not claim full end-to-end success until this actual click is observed. Avoid launching a second diagnostic app while keeping Dock menu open.

All changes are on `feat/macos-adaptive-title-helper`, Draft PR #3 unmerged; Windows source untouched.
