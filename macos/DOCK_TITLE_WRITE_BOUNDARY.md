# Dock window-item title: native write boundary (2026-10-16)

## Goal, strictly

The owner wants the window list in the macOS Dock context menu for ChatGPT to display distinct *native window titles* reflecting the already-existing conversation titles, e.g. "ChatGPT" -> "TitleHelper AX 테스트". This does **not** require renaming any ChatGPT conversation, pressing a title button, typing, or focusing a ChatGPT window during routine operation.

The event-driven AX observer obtains the conversation title from AXWebArea.Title. The Dock native item is backed by the owning app's window title, distinct from AXWebArea.Title.

## Verified event telemetry following owner's manual title rename

ChatGPT AX title changed from len42:shaee1876263c82 to len18:shacd4ee6ac07d9.
Two AXValueChanged events were received at 2026-10-16 00:11:15 and 00:11:17 KST (2026-10-15T15:11Z). Both immediate event-driven title reads still returned the old 42-character title, as the app hadn't committed the change yet. The newly committed 18-character title was first captured by the next 20-second fallback at 00:11:39 KST. **Hence immediate title-change propagation is not yet complete**, despite proper AX notification delivery.

## Actual native title attribute write-capability test

macOS 26.6.2, ChatGPT 26.1007.71326. The stable-signed, Accessibility-approved ChatGPTTitleProbe gained a strictly read-only "inspect-window-title" mode and inspected the actual ChatGPT AXWindow:

- AXWindow.AXTitle = "ChatGPT" (len7:sha50a412294327).
- AXUIElementCopyAttributeNames: success, AXTitle supported=true.
- AXUIElementIsAttributeSettable(AXTitle): status 0 (successful query), writable=false.
- AXTitle was **not written**. No ChatGPT conversation was changed.

The documented Apple Accessibility API does not permit an external helper to set the AXTitle property for this window.

## Isolated WindowServer/SkyLight SPI experiment, not against ChatGPT

Private symbol CGSSetWindowTitle is present on macOS 26.6.2. To distinguish API existence from actual cross-process write authority, we used a disposable independently-owned Cocoa test window (title "NativeTitleLab Original"), not any ChatGPT window.

- Process A owning a synthetic window, WindowID=46705; process B calling CGSSetWindowTitle with the B process connection -> **return 1000** (generic failure).
- Separate process C owning its own synthetic Cocoa window, WindowID=46708, calling the *identical* CGSSetWindowTitle function with its own connection -> **return 0** (success).
- The synthetic test windows were closed and the test processes ended. No code was injected into ChatGPT, no TCC permissions altered, no process was signaled, no app binary modified.
- This pair of results supports a process-ownership boundary. It does **not** establish that every private API variant is universally impossible. CGSSetWindowTitle is private/unsupported for production anyway.

References:
- Apple NSWindow.title property: https://developer.apple.com/documentation/appkit/nswindow/title
- Apple AXUIElementIsAttributeSettable: https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable
- Electron Dock: https://www.electronjs.org/docs/latest/tutorial/macos-dock
- Historical CGSSetWindowTitle declaration: https://gitlab.com/gnachman/iterm2/blob/adhoc_3.1.20171013_214551/ThirdParty/CGSInternal/CGSWindow.h


### Owner-connection-ID control (additional experiment)

A second isolated disposable native Cocoa window (WindowID 46709) exposed its genuine owning SkyLight connection ID 950891 to the separate caller (connection 292067). The external caller passed either the **owner's actual connection ID** or its **own connection ID** to CGSSetWindowTitle. Both calls returned error 1000. Therefore substituting the owner connection number is not sufficient to bypass the cross-process failure; the WindowServer enforces more than the supplied numeric connection ID (or otherwise rejects the request). No ChatGPT window was targeted.

## Existing native write path and safe production stance

Legacy NativeTitleSync uses Electron BrowserWindow.setTitle through Node main-process Inspector, normally on port 9229. The 2026-10-15 forensic macOS launchd logs conclusively showed ChatGPT twice exited due to SIGUSR1 **sent by ChatGPTTitleOverlay**. The current ChatGPT's Electron V1 fuse EnableNodeCliInspectArguments=0 disables both SIGUSR1 and --inspect. The class is preserved unmodified for reference; default compiled helper keeps all callers of NativeTitleSync.sync / restore unreachable.

Nothing in the current experiments justifies re-enabling the original Inspector fallback, flipping the target app fuse, re-signing official ChatGPT, injecting a library, or patching Dock process memory. Such work would breach app integrity/unsupported boundaries and needs a new explicit design review rather than blind retries.

## Next executable choices

1. Fix pending AX event/read lag independently: when a value-change event occurs but the old title is still read, schedule a small bounded series of deferred, targeted AXWebArea.Title reads (not full-tree 0.5s polling), clearing attempts on title change; measure event-to-title latency.
2. For native Dock menu item changes, use an integration that legally runs *inside* the window-owner process or a supported ChatGPT app hook, if one becomes available. Current installed ChatGPT does not expose an authenticated supported window-title setter; preserve the safe fail-closed state.
3. If in-process integration is unavailable, a distinct user-owned menu/window switcher could display already-detected conversation titles, **but it cannot silently replace the native ChatGPT Dock window list**. This is a different UX and requires owner consent.

## Rollout state

At conclusion ChatGPT and the safe TitleHelper remained running. The temporary TitleAXProbe was updated using the same stable TheCompany 2036 signing identity and the existing Bundle ID; it was run only for the read-only capability check. TitleHelper's AX event code and NativeTitleSync source were not modified during this feasibility study. Draft PR #3 remains draft, no merge.
