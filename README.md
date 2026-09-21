# ChatGPT Window Title Helper

Utilities for exposing ChatGPT conversation titles at the operating-system window level.

This repository contains separate implementations for Windows and macOS.

## Windows

The original Windows implementation is preserved under [`windows/`](windows/).

It is a Windows x64 tray utility that reads ChatGPT conversation titles through UI Automation and can show an overlay or change the native Alt+Tab/window title.

See [`windows/README.md`](windows/README.md) for Windows compatibility, usage, and build instructions.

## macOS

The macOS implementation is under [`macos/`](macos/).

It is a Swift menu-bar helper that reads the ChatGPT Accessibility tree, can show a non-activating title overlay, and can optionally synchronize the native/Dock window title through the Electron main-process inspector.

See [`macos/README.md`](macos/README.md) for:

- verified build environment,
- complete build and installation instructions,
- Accessibility permission setup,
- ad-hoc signing/TCC rebuild notes,
- usage and native-title synchronization details,
- known limitations.

Quick local build/install:

```bash
cd macos
chmod +x build.sh
./build.sh
```

The script builds, ad-hoc signs, installs, and launches:

```text
~/Applications/ChatGPTTitleOverlay.app
```

## Compatibility note

Both implementations depend on implementation details of the ChatGPT desktop app and may require updates when the app changes.

## Repository layout

```text
.
├── LICENSE
├── NOTICE
├── README.md
├── windows/   # Original Windows implementation and documentation
└── macos/     # macOS Swift implementation and build/install guide
```

## License and attribution

Copyright 2026 harshlad79.

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) for the full license terms.

The original project and attribution information are recorded in [`NOTICE`](NOTICE).

Original project: https://github.com/harshlad79/chatgpt-window-title-helper

## Status

Source archive / maintenance mode. The code is kept public for reuse and future updates.
