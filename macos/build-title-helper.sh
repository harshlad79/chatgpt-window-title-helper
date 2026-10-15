#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/artifacts/macos"
cd "$ROOT"
xcrun swiftc -O \
  macos/ChatGPTTitleHelper.swift \
  macos/MacAXTitleObserver.swift \
  macos/DockMenuSidecar.swift \
  macos/TitleWorkScheduler.swift \
  macos/TitleRevisionRetryPlan.swift \
  macos/TitleHelperDiagnostics.swift \
  macos/main.swift \
  -o artifacts/macos/ChatGPTTitleHelper \
  -framework Cocoa -framework ApplicationServices -framework QuartzCore
echo 'BUILT artifacts/macos/ChatGPTTitleHelper (not installed or launched)'
