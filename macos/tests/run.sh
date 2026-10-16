#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/artifacts/macos"
python3 macos/tests/verify_native_sync.py
out="$(mktemp "$ROOT/artifacts/macos/.scheduler-test.XXXXXXXX")"
trap 'rm -f "$out"' EXIT
xcrun swiftc macos/TitleWorkScheduler.swift macos/TitleRevisionRetryPlan.swift macos/WindowSessionHistoryStore.swift macos/TitleHelperDiagnostics.swift macos/tests/main.swift -o "$out"
"$out"
./macos/build-title-helper.sh
bash -n macos/build-title-helper.sh
