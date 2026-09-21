# ChatGPT Window Title Helper

Windows tray utility for showing the current ChatGPT conversation title on each ChatGPT window.

## Compatibility

- Platform: Windows x64
- Verified with Codex/ChatGPT desktop app version `26.908.40834` (released 2026-09-12)
- Compatibility is currently limited to the Korean UI of that desktop-app version because SectionHeader and action detection rely on its Korean UIA structure and labels.
- The app identifies windows by native HWND and supports multiple ChatGPT windows.
- Published builds are self-contained .NET 8 x64 single-file applications; end users do not need to install .NET separately.
- Building from source requires the .NET 8 SDK x64.

## Verified build environment

The final Windows build was verified with:

- OS: Windows `10.0.26200`
- Architecture / RID: `win-x64`
- .NET SDK: `8.0.425`
- SDK path: `C:\Program Files\dotnet\sdk\8.0.425\`
- dotnet executable: `C:\Program Files\dotnet\dotnet.exe`
- MSBuild: `17.11.48+02bf66295`
- .NET Host: `8.0.31` x64
- Microsoft.WindowsDesktop.App: `8.0.31`
- Target framework: `net8.0-windows`

No `global.json` was used in the verified environment.

## Usage

Run the published `ChatGPTWindowTitleHelper.exe`. The tray menu provides:

- `Status`
- `Show Conversation Title`
- `Change Alt+Tab Title`
- `Exit`

Settings are stored at `%LocalAppData%\ChatGPTWindowTitleHelper\settings.json`.

The app discovers top-level `ChatGPT.exe` windows by HWND and reads each window's UI Automation conversation title. UIA work is dispatched independently per HWND; a second operation for the same HWND is skipped while the first is running, and each completed result is applied only to its own window. The optional in-window overlay is shown only when the SectionHeader does not already contain a button named with the conversation title. It uses the detected header/action bounds and avoids the right-side action area, including `Share`.

The overlay follows the target window using the last successful HWND-relative geometry and does not activate or take focus. Conversation-title UIA refresh currently uses a 2-second polling cycle. UIA results collected during move/resize are discarded, and a fresh per-window read is scheduled after movement ends.

## Build

Requires .NET 8 SDK x64.

From the `windows` directory:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish.ps1
```

The script publishes a self-contained x64 single-file executable to:

```text
artifacts\publish\win-x64\ChatGPTWindowTitleHelper.exe
```

Build artifacts are intentionally excluded from source control.

### UI Automation reference paths

The project currently references the UI Automation assemblies from the Windows Desktop Runtime used by the verified build:

```text
C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\8.0.31\UIAutomationClient.dll
C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\8.0.31\UIAutomationTypes.dll
```

These paths are explicitly specified in `src\ChatGPTWindowTitleHelper\ChatGPTWindowTitleHelper.csproj`.

If your installed .NET 8 Windows Desktop Runtime has a different patch version, update the two `HintPath` values in that project file to match your installed version. You can check installed runtime versions with:

```powershell
dotnet --list-runtimes
```
