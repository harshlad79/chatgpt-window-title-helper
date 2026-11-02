# Native multiwindow session history and Dock Recent restore

Date: 2026-10-16 KST. Canonical feature implementation SHA:
`25a738d595dcce40d7cacc627fb8aa31a92898d2`.
Draft PR #3 remains unmerged; the Windows implementation and original NativeTitleSync were not changed.

## Confirmed native actions

1. Stable-signed TitleAXProbe enumerated macOS ChatGPT's **native menu bar**.
2. Native menu item `파일 → 새 창` was uniquely found, enabled, and supported AXPress.
3. Verified live invocation: AXPress returned success 0, `AXWindows` increased from 1 to 2. Prior chat window remained intact; new window initially had `AXWindow.AXTitle = "ChatGPT"`.
4. Opened the ChatGPT Dock icon's `Recent → second More` AXMenu. A screenshot-grounded exact recent conversation title matched **once** in 59 available items; pressing that one AXMenuItem returned success 0.
5. Verified after navigation: `AXWindows` remained 2. The new window's AXWindow.AXTitle became the chosen exact conversation (`len17:sha94056e7278e0`), and the former existing window retained its unrelated original title (`len18:shae72cacec25a6`). **This establishes separate native windows** and does not merely replace the content of the original window.
6. The same conversation was earlier separately confirmed by the owner to load its body normally when opened via Dock Recent. Owner confirmation of the combined new-window-then-Recent chat body was not specifically collected; here the native window-title and preservation E2E are the confirmed observations.

The user specifically corrected the prior design: Dock Recent items alone navigate/reuse the *existing* window. Therefore the **new window must be created first** for each desired separately restored conversation.

## Installed feature

`macos/WindowSessionHistoryStore.swift`
- Locally stores human-readable conversation window titles in
  `~/Library/Application Support/ChatGPTTitleOverlay/window-session-history.json`.
- Uses Foundation Codable v1 and atomic JSON replacement.
- Stores last *complete* open-window title census, prior ChatGPT process session window names, recent title history and ChatGPT PID.
- Does not erase a complete snapshot when AX fails, when zero windows are returned transiently, or while only some window titles have been refreshed. On detecting a new ChatGPT PID, moves the prior complete list into the previous-session snapshot.
- Limits recent titles to 250; user selection UI shows up to eight recoverable titles. Data is local and not automatically sent anywhere.
- Deliberately title-based **best-effort** because AXWebArea.URL is generic, sidebar AXButton.URL/DOMIdentifier empty, and Dock AXMenuItem.URL absent. No unsupported claim of unique conversation IDs.

`macos/DockRecentWindowRestorer.swift`
- Preflight: actual app accessible, target title non-empty; unique exact match in Dock's second Recent/More submenu. **No window created** for missing or duplicate title.
- Invokes enabled `파일 → 새 창` through AXPress. Checks an actual extra new AXWindow with initial generic "ChatGPT" title.
- Re-reads the Dock Recent menu (never reuse stale AX handles), presses uniquely matched recent item, checks the correct newly created AXWindow title and preservation of every previous window identity.
- User-triggered only; never bulk-launches or automatically recreates all windows. No task hooking, Inspector, SIGUSR1 or app patch.
- On an action failure after creating a blank new window, does not blindly close a window; reports the error for user recovery.
- Existing UI uses a nonactivating sidecar panel; validation of the **integrated history button click** and resulting new window from within the live panel is still pending.

`macos/DockMenuSidecar.swift`
- Retains the current AX-identity-based list of active windows.
- Adds a lower section `이전에 열었던 대화` with clickable prior history titles, excluding currently open titles.
- Only renders this section after real records exist; immediately after first install, all known titles may still be current, hence history=0 is expected.
- Keeps Dock menu separate and unmodified.

`macos/ChatGPTTitleHelper.swift`
- Feeds only full AX-title censuses into the history store and refreshes the sidecar with recoverable history.
- On history row click, calls the restorer and reports a modal warning on failure. A new window is always attempted before Dock Recent action.

## Test, deployment, and limitations

- Local source compiled; **41 Swift assertions** passed, including incomplete AX census preservation, helper restart JSON reload, ChatGPT PID change, previous-session retention, filtering reopened windows, untitled window refusal.
- Existing NativeTitleSync exact byte-identity check PASS and unsafe Inspector calls compiled out.
- The source was pushed through GitHub base64 blob/tree (no tool-output masking), then **rebuilt from a separate clean checkout** of exact SHA `25a738d`. New files were byte-identical to the tested source, no placeholders.
- A remote Mac deployment request returned `status=failed` after 60,186ms with `mcp_path=control-n150/thecompany-chatgpt-mcp -> control.invoke -> macos-main`, with no detailed worker error. Rather than blindly repeat, a subsequent read-only reconciliation proved the signed installed executable was updated, a rollback backup was created, and the new helper had launched PID 46070 while ChatGPT PID 35112 remained running.
- Runtime: signed helper stable, two known AX chat titles, 26 observer subscriptions, local JSON with current appPID 35112, `lastCompleteOpen=2`, `recentTitles=2`, `previousSessionOpen=0`.
- Reopened actual ChatGPT Dock menu after deployment: sidecar displayed and AX confirmed two current title buttons. Since both titles were currently open, history=0 was correct.
- User should verify after closing a *known*, safe test conversation window: Dock icon right click → sidecar `이전에 열었던 대화` → that title. Observe that a **new** native ChatGPT window opens and all earlier windows stay unchanged. No user window was closed automatically as part of this deployment.
- Limitation: same-titled distinct conversations cannot be disambiguated by AX. A duplicate in current Dock Recent stops restore rather than select the wrong chat. An unavailable/evicted Dock Recent title cannot be restored by this method. The Dock's recent list long-term persistence across actual app crashes remains unverified. Full automatic bulk restore not implemented.
- Stored titles are plaintext in a user-local Application Support JSON. Do not include URLs/messages or hidden app API tokens.
