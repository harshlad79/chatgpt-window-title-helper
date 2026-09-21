# ChatGPT Window Title Helper

Utilities for exposing ChatGPT conversation titles at the operating-system window level.

This repository contains separate implementations for Windows and macOS.

## Windows

The original Windows implementation is preserved under [`windows/`](windows/).

It is a Windows x64 tray utility that reads ChatGPT conversation titles through UI Automation and can show an overlay or change the native Alt+Tab/window title.

See [`windows/README.md`](windows/README.md) for the original Windows documentation, build instructions, constraints, and compatibility notes.

## macOS

The macOS implementation is under [`macos/`](macos/).

Files:

- `ChatGPTTitleOverlay.swift` — menu-bar helper.
- `build.sh` — builds and launches `~/Applications/ChatGPTTitleOverlay.app`.

Current features:

- Reads the conversation title from the ChatGPT desktop app Accessibility tree (`AXWebArea.AXTitle`).
- Optional non-activating title overlay for the active ChatGPT window.
- Optional Dock/native window-title synchronization.
- Native-title synchronization enables the Electron main-process inspector with `SIGUSR1` when needed and uses Electron `BrowserWindow.setTitle()`.
- Overlay and native-title synchronization can be enabled independently from the menu-bar item.

### macOS requirements

- macOS with the ChatGPT desktop app.
- Swift command-line build tools (`xcrun swiftc`).
- Accessibility permission for ChatGPT Title Overlay.
- The current target ChatGPT bundle identifier is `com.openai.codex`.

### Build

```bash
cd macos
chmod +x build.sh
./build.sh
```

The script creates:

```text
~/Applications/ChatGPTTitleOverlay.app
```

The current script uses ad-hoc code signing (`codesign --sign -`). This is suitable for local/source builds, but rebuilding can cause macOS Accessibility/TCC permission identity issues. A packaged public binary should use a stable Developer ID signature and notarization.

### Compatibility note

Both implementations depend on implementation details of the ChatGPT desktop app and may require updates when the app changes.

## Repository layout

```text
.
├── windows/   # Original Windows implementation and documentation
├── macos/     # macOS Swift implementation
└── README.md
```

## Status

Source archive / maintenance mode. The code is kept public for reuse and future updates.
