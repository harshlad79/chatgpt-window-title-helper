# ChatGPT Window Title Helper

Windows tray utility for showing the current ChatGPT conversation title on each ChatGPT window.

## Compatibility

- Platform: Windows x64
- Verified with Codex/ChatGPT desktop app version `26.908.40834` (released 2026-09-12)
- Compatibility is currently limited to the Korean UI of that desktop-app version because SectionHeader and action detection rely on its Korean UIA structure and labels.
- The app identifies windows by native HWND and supports multiple ChatGPT windows.
- Published releases are self-contained .NET 8 x64 single-file applications; end users do not need to install .NET separately.
- Building from source requires the .NET 8 SDK x64.

## Usage

Run the published `ChatGPTWindowTitleHelper.exe` from the local publish output. The tray menu provides:

- `Status`
- `Show Conversation Title`
- `Change Alt+Tab Title`
- `Exit`

Settings are stored at `%LocalAppData%\\ChatGPTWindowTitleHelper\\settings.json`.

The app discovers top-level `ChatGPT.exe` windows by HWND and reads each window's UI Automation conversation title. UIA work is dispatched independently per HWND; a second operation for the same HWND is skipped while the first is running, and each completed result is applied only to its own window. The optional in-window overlay is shown only when the SectionHeader does not already contain a button named with the conversation title. It uses the detected header/action bounds and avoids the right-side action area, including `Share`.

The overlay follows the target window using the last successful HWND-relative geometry and does not activate or take focus. Conversation-title UIA refresh currently uses a 2-second polling cycle. UIA results collected during move/resize are discarded, and a fresh per-window read is scheduled after movement ends.

## Build

Requires .NET 8 SDK x64.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish.ps1
```

The output is a self-contained x64 single-file executable in the output directory selected by the publish command. Build artifacts are intentionally excluded from source control.
