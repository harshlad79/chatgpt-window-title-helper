# macOS ChatGPT AX control: verified implementation and future extraction

Status: VERIFIED locally on macos-main, October 15, 2026.
Source: macos/TitleAXProbe.swift, branch feat/macos-adaptive-title-helper.
Keep macOS workstream on Draft PR #3 until full title-helper product review.
The legacy TitleOverlay and Windows production implementation were not modified.

## Scope

This is a narrowly scoped, signed, owner-authorized *ChatGPT-specific* AX test
client. It is NOT a general-purpose macOS accessibility automation service.
Its action modes accept one exact conversation title as an optimistic
concurrency precondition, identify the process by Bundle ID com.openai.codex,
verify exactly one matching AXWebArea.Title window, and refuse ambiguity.
It does not expose arbitrary AppleScript, shell commands, generalized
element clicking, or raw UI text in its diagnostic log.

The helper's Bundle ID is local.chatgpt.titleprobe. The stable, existing
2036 TheCompany self-signed *local* code-signing certificate is used:
public SHA-1 EBC7B73928C50D22D965AFE909AB5CBD519FB851.
No private key, certificate, TCC database or user data is stored in Git.
Certificate reuse preserves the user's Accessibility grant in actual local
updates. It does not establish universal macOS TCC behavior.

## API and behavior established on the real Mac

1. NSWorkspace.runningApplications finds ChatGPT's exact Bundle ID.
2. AXUIElementCreateApplication(pid) and AXWindows find ChatGPT windows.
3. AXWebArea.Title contains the actual conversation title independently of
   the window's generic AXTitle (normally "ChatGPT").
4. A unique AXButton.Title matching that exact title supports AXPress.
   Pressing it opens an inline title editor without mutating conversation data.
5. A unique AXTextField.AXValue equal to the old title appears in the same
   window. AXValue is reported as writable.
6. AXUIElementSetAttributeValue(field, AXValue, newString) returned AXError=0,
   **but the React/Electron input did not change**. Do not use this as proof of
   editing merely because the return code says success.
7. CGEventPostToPid with Command+A followed by a Unicode keyboard event can
   replace the text in the focused field. It is **not sufficient** for the
   app to be active: with another ChatGPT window focused, events did NOT reach
   the intended field. The original title remained untouched in that trial.
8. Check BOTH NSRunningApplication.isActive and
   AXUIElementCopyAttributeValue(app, AXFocusedWindow). Exact target window
   has AXRaise, which was confirmed to focus the target. The safe roundtrip
   also activates ChatGPT with NSRunningApplication.activate when needed and
   rechecks focus before sending every key.
9. CGPreflightPostEventAccess() must be true. No generic osascript
   Accessibility approval is needed or recommended.
10. Enter (virtual keycode 0x24) commits the edit. Verify the NEW title via
    AXWebArea.Title, reopen the title editor, restore the ORIGINAL title by
    the same keyboard path, Enter again, and independently verify the old
    AXWebArea.Title.
11. AXTitleChanged alone is **not** a conversation title proof; unrelated
    AXStaticText sources were observed to emit it. Compare title string
    fingerprints or the exact AXWebArea.Title after the event.

## Verified real end-to-end cases

- Exact old title length: 42 Unicode characters.
- Single-character Korean temporary title: "가" (length 1).
  temporaryCommitted=true; originalRestored=true.
- Single-character English temporary title: "A" (length 1).
  temporaryCommitted=true; originalRestored=true.
- Several independent later AX reads found exactly one window with the
  original title. No rollback record remained after successful restoration.
- A deliberately nonexistent expected title was rejected before any mutation:
  expected-title-window-ambiguous, matches=0.
- A different ChatGPT window was focused during an earlier dry run; the
  preflight refused keyboard events until AXRaise focused the exact target.
- The app was repeatedly repackaged with the same certificate and its
  Accessibility approval remained valid. The installed bundle passed
  codesign --verify --deep --strict; designated requirement:
  identifier "local.chatgpt.titleprobe" and certificate leaf =
  H"ebc7b73928c50d22d965afe909ab5cbd519fb851".

## Invocation and permission attribution

The main AX probe app must be opened via macOS LaunchServices for its
existing TCC identity to apply. Direct execution of
ChatGPTTitleProbe.app/Contents/MacOS/ChatGPTTitleProbe by the TheCompany
node-agent shell produced AXIsProcessTrusted=false even though the same
signed app launched with open -a reported true. This distinction was
reproduced on macos-main; do not assume it holds identically on all Macs.

The following are distinct, allowlisted modes in the same executable:
- inspect-actions: read-only enumeration of actions/writability for an exact
  conversation title, no raw text logging.
- open-title-button: AXPress only if the exact title's button is unique.
- raise-target-window: AXRaise only the verified window.
- test-title-field: reversible AXValue trial (known not effective here).
- test-title-keyboard: reversible keyboard input trial (no Enter/save).
- rename-and-restore: commits a requested temporary title, verifies it,
  then restores and verifies the original title within one bounded run.

Run from TheCompany Dev MCP on macos-main, NOT Core operating tooling.
Illustrative local invocation (replace the placeholders in quotes):

  open -a "$HOME/Applications/ChatGPTTitleProbe.app" --args \
    inspect-actions "<EXACT_OLD_CONVERSATION_TITLE>"

  open -a "$HOME/Applications/ChatGPTTitleProbe.app" --args \
    rename-and-restore "<EXACT_OLD_CONVERSATION_TITLE>" "<TEMP_TITLE>"

The packaging script only updates an existing app bundle, preserves a
rollback copy under ignored artifacts/macos/backups, signs the staged app
exactly once using the 2036 TheCompany certificate and checks its DR.
Use APP_PATH when the installed location differs; do not create an
unexpected ~/Applications folder. Never alter the old overlay app.

## Safety and recovery contract

- Before editing: target ChatGPT bundle ID, unique AXWebArea exact title,
  active app, correct AXFocusedWindow, focused AXTextField with identical
  AXValue, and CGPreflightPostEventAccess must all be satisfied.
- No title-length assumption: one-character titles are valid.
- Check the field readback after typing and exact AXWebArea.Title after Enter.
  An AX API success code or a generic title-change notification is not proof.
- Before any persistent test, write a local owner-only 0600 recovery file at
  ~/Library/Logs/ChatGPTTitleHelper/title-probe-rollback.txt.
- Remove the recovery file ONLY after the original title is confirmed.
  On failure, stop and inspect the remaining file/actual UI. Never guess a
  target or perform a destructive action.
- Diagnostic title fingerprints are SHA-256 prefix + length; avoid collecting
  conversation bodies. Logs and recovery files are excluded from Git.
- A stable certificate helps maintain TCC continuity, but neither the
  Bundle ID nor the source-level target check is an OS-enforced app sandbox.
- If ChatGPT or the user changes focus during execution, the test must stop
  rather than posting further keys to an unrelated window.

## Future dedicated GUI control app

Extract into a separate signed app only when broad GUI control is needed:
- An AX target resolver checks running application Bundle ID, expected title,
  unique window and current element identity.
- An AX capabilities/read-only inspector handles actions, attr settable
  checks, readback and event correlation.
- A constrained title driver handles AXPress, verified AXRaise,
  target-specific Unicode events and Enter; no unrestricted scripting.
- A transaction guard maintains expected old value, 0600 rollback material,
  postconditions, permission checks and human intervention on failure.
- A broker/IPC layer exposes explicit allowlisted operations; do not grant
  Accessibility to generic Python, shell or osascript interpreters.
- Preserve independent signing identity, Bundle ID and TCC consent for
  each future helper app; do not reuse the probe's identity for unrelated apps.

The **macOS native window/Dock title mutation** (as opposed to *conversation
rename*) is a DIFFERENT, still-unverified feature. Existing macOS AXWindow
AXTitle was read-only. Do not conflate the successful conversation rename
with native window-title editing; do not enable the unverified legacy
Electron inspector/SIGUSR1 path in the diagnostic app.

Canonical policies:
https://github.com/harshlad79/thecompany-core/blob/main/docs/operations/macos-app-signing-identity.md
https://github.com/harshlad79/thecompany-browser/blob/main/docs/operations/macos-local-code-signing.md

Official Apple APIs:
https://developer.apple.com/documentation/applicationservices/1462053-axuielementcopyactionnames
https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction
https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()
https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)
