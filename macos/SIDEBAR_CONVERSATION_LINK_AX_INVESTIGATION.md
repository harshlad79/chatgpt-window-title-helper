# macOS ChatGPT conversation restore: sidebar AX link census (2026-10-16)

Goal: Persist windows' actual conversation identities and use them to reopen previously open conversations after the ChatGPT app crashes or restarts. Never restore from title alone because identical titles are possible.

## Owner hypothesis

Clicking a conversation entry in the ChatGPT left sidebar navigates to that conversation; its UI element might expose a durable per-conversation link or ID. Test the native macOS ChatGPT Accessibility tree before designing storage or restoration.

## Test conditions

TheCompany-Dev macos-main. Running ChatGPT PID 80584, two windows. Stable-signed TitleAXProbe with granted macOS Accessibility permission; private scratch probe only, not production TitleHelper. All observations read-only except the single native UI sidebar toggle, which was pressed then restored. No chat entry was clicked; no conversation or official ChatGPT binary was altered; no raw URLs/IDs/chat text were logged.

- Both windows each had one AXWebArea.Title matching the actual conversation. AXWebArea.AXURL exists, but has length 18, scheme `app`, and identical fingerprint `6da5fe391369` across both windows. This URL is not a distinct conversation locator.
- Each window had one AXLink with an AXURL of length 25 (scheme `app`, distinct values by fingerprint `929d60c82e63` / `02fdbe6d6be3`). Critically, both AXLinks have the SAME 10-character label/description fingerprint `22dbf389cc54`, physical size only **2x2** and top-of-window coordinates (210,187) / (737,161). URL structure: host length 1, path length 11, one path segment, fragment length 6. Neither `/c/` nor `/threads/` appears. This is NOT proven to represent a sidebar conversation link and should NOT be persisted as a conversation ID.
- Initially, traversing normal AXChildren exposed 85/86 AX nodes, AXButton 16 each, AXLink 1 each, no sidebar conversation list.
- A uniquely identifiable AXButton titled **"사이드바 보기"** existed in each window (top toolbar). An owner-authorized AXPress on only the first window returned 0. A second AXPress to restore the control also returned 0.
- Immediate scan following the press still showed 85/86 nodes, and the same single AXLink per window. A further scan traversed AXChildren, AXVisibleChildren, AXContents and AXChildrenInNavigationOrder with de-duplication (262/244 visited), but still only one AXLink per window and no per-conversation navigation URL.
- Native ChatGPT PID remained alive.

## Interpretation

The owner's hypothesis is plausible: a rendered conversation row may internally carry an ID or trigger navigation through JS, even when neither AXURL nor AXLink is provided by the current Accessibility subtree. The small per-window AXLink is likely a different UI/internal navigation element; we did **not** establish what it targets. Therefore do not mistake distinct URL hashes for distinct conversation IDs.

No native thread URL was recovered from the tested AX state. Next required **manual UI state**: have the owner physically expand the left sidebar until multiple conversation entries are visibly listed. Inspect those exact visible rows, their AXURL/AXIdentifier/AXValue/AXDescription/AXActions, including other accessibility surfaces and navigation events. Avoid clicking a conversation until a reversible E2E probe is designed. Alternatively test the user-accessible built-in "Copy chat deep link" feature on a single window, then verify link routing into a new *native* ChatGPT window before implementing persisted session restoration.

The restore design should persist conversation ID/URL, title, lastSeen and lastActive ordering; distinguish history vs. last-session window set, and support selected or all restoration. The practical runtime link and open-in-new-window behavior remain unverified.
