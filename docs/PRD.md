# ChatGPT Window Title Helper — PRD v1

상태: 1차 구현 기준 확정안

## Product goal

Windows x64 tray utility that helps distinguish multiple ChatGPT desktop windows by reading each window's current conversation title through Windows UI Automation (UIA).

The utility must not automate ChatGPT input, force activation, steal focus, or interfere with normal mouse and keyboard use.

## v1 scope and behavior

- Finds top-level ChatGPT windows by HWND, not by PID or window title.
- Tracks multiple windows from the same ChatGPT process independently.
- Reads the current conversation from the UIA element whose `AriaProperties` contains `current=page`; its `Name` is used as the conversation title.
- Runs UIA work independently for each HWND.
- Prevents overlapping UIA work for the same HWND.
- Applies a completed result only to the HWND that requested it.
- Shows an in-window title overlay only when the SectionHeader does not already contain a button named with the conversation title.
- Uses the last successful overlay geometry and the current HWND position for movement tracking.
- Overlay positioning has one global invariant: never retain or reuse a screen-absolute
  overlay position. A successful UIA result may update only the layout relative to the
  target HWND's top-left corner. Every repaint, move/resize update, and fallback placement
  must first read the target HWND's current screen rectangle and calculate
  `current HWND top-left + stored relative offset`. This rule applies regardless of z-order,
  foreground state, maximized state, or whether UIA is currently running.
- Document.Name and SectionHeader are read from the same freshly acquired UIA Document
  tree for one window operation. Document.Name supplies the conversation title; the
  SectionHeader structure independently determines whether an overlay is needed.
- The literal value `ChatGPT` is treated as the sentinel only on exact, case-insensitive
  equality. Partial matches containing `ChatGPT` must not be treated as the sentinel.
- Overlay windows are non-activating and click-through.
- Supports optional Alt+Tab window-title replacement.
- Provides tray options for conversation overlay, tray inspector, Alt+Tab title replacement, status, and exit.
- Uses a 2-second refresh interval.
- Stores settings under `%LocalAppData%\\ChatGPTWindowTitleHelper\\settings.json`.
- Publishes as a Windows x64 self-contained .NET 8 single-file executable.

## v1 limitations

- UIA calls already in progress cannot be safely interrupted mid-call.
- Move/resize start and end events are not part of v1. During a long move or resize, a completed UIA operation may therefore be followed by a later polling operation.
- UIA results are associated with their HWND and same-HWND overlapping operations are prevented, but v1 does not interrupt an already running UIA call.
- UIA structure can change while ChatGPT is running; failed reads retain the last successful title and geometry where possible.
- A UIA title read succeeding does not imply that SectionHeader was read successfully.
  The title and SectionHeader result must be applied as one HWND-scoped operation; if the
  SectionHeader read fails, preserve the previous overlay visibility decision and relative
  geometry rather than replacing it with a screen coordinate, HWND origin, or an Unknown result.
- When the conversation title is already visible, or the window is minimized, the overlay
  is hidden temporarily; it is not removed or disposed. The HWND's overlay object and last
  successful relative geometry remain available for restoration.
- When UIA fails, do not hide, show, recreate, or reposition the overlay based on the failed
  result. Keep the last known visibility and relative geometry until a new coherent
  Document/SectionHeader result is available.

The following are deliberately deferred to a later version: move/resize event gating, generation-based invalidation of results started before a move, and a single post-stabilization UIA refresh.

## Compatibility

- Windows x64
- Verified against Codex/ChatGPT desktop app version `26.908.40834`, released `2026-09-12`
- Building from source requires the .NET 8 SDK x64.
- Published self-contained builds do not require a separate .NET runtime.

## Explicitly out of scope

- DOM modification, DLL/code injection, OCR, image recognition
- Mouse or keyboard automation
- Forced sidebar opening or window activation
- Manual title entry
- Installer and automatic updater
- Public release artifacts committed to the source repository

## v1 acceptance criteria

1. Multiple ChatGPT windows are tracked independently by HWND.
2. Each window receives only its own UIA result.
3. A title overlay appears only where the conversation title is not already visible.
4. Overlay interaction does not block mouse input or keyboard focus.
5. Alt+Tab title replacement can be enabled independently.
6. Tray controls and clean exit work.
7. Temporary UIA failures do not terminate the utility.
8. A Windows x64 self-contained single-file build can be produced from source.
9. The source repository contains source, tests, scripts, documentation, and the PRD, but not local build artifacts or SDK caches.
