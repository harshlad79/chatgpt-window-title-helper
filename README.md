# ChatGPT Window Title Helper

Windows tray utility for showing the current ChatGPT conversation title on each ChatGPT window.

## Compatibility

- Platform: Windows x64
- Scope: **Windows-only** (`WinForms` + Win32 `HWND` + Windows UI Automation). macOS is **not supported by this implementation**; a Mac version must be developed and tested separately.
- Verified with Codex/ChatGPT desktop app versions `26.908.40834` (2026-09-12) and `26.1007.2314.0` (2026-10-12).
- The 2026-10 app exposes conversation titles as `Document.Name` and a matching visible title `Button` in the document's header toolbar (rather than `SectionHeader`). The helper prioritizes this button and does not overlay the native title. Legacy Korean `SectionHeader` handling remains as fallback.
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

The app discovers top-level ChatGPT.exe windows by HWND. On first discovery it
reads the conversation UIA Document.Name, locates the native header title
Button, and subscribes to that Button's NameProperty changes. Live Windows
experiments confirmed that the Button event fires on conversation renames,
whereas the Document NameProperty event did not.

All UIA reads and event subscriptions run on one dedicated MTA worker with a
priority-promotable, HWND-deduplicated queue. New and active windows are
prioritized. Stable windows receive a staggered 20-second fallback check:
only one overdue window enters the queue per 2-second discovery tick.
Failed or untitled windows use 2-to-30-second backoff. A native header is
classified once and is not retraversed on ordinary title checks.

The WinEvent name-change hook ignores child accessibility events. Foreground
changes prioritize the selected ChatGPT window. Native title buttons suppress
the duplicate title overlay. Moving/resizing retains last known geometry.

This implementation targets Windows; macOS requires a separate implementation.

## Build

Requires .NET 8 SDK x64.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish.ps1
```

The output is a self-contained x64 single-file executable in the output directory selected by the publish command. Build artifacts are intentionally excluded from source control.
