#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/artifacts/macos"
python3 macos/tests/verify_native_sync.py
out="$(mktemp "$ROOT/artifacts/macos/.scheduler-test.XXXXXXXX")"
menu_test="$(mktemp "$ROOT/artifacts/macos/.menu-test.XXXXXXXX")"
trap 'rm -f "$out" "$menu_test"' EXIT
xcrun swiftc macos/TitleWorkScheduler.swift macos/TitleRevisionRetryPlan.swift macos/WindowSessionHistoryStore.swift macos/WindowSessionRestoreQueue.swift macos/TitleHelperDiagnostics.swift macos/tests/main.swift -o "$out"
"$out"
xcrun swiftc macos/ConversationRouteIdentity.swift macos/FocusedMenuURLProbe.swift \
  macos/tests/menu_probe/main.swift -o "$menu_test" \
  -framework Cocoa -framework ApplicationServices
"$menu_test"
./macos/build-title-helper.sh
bash -n macos/build-title-helper.sh
