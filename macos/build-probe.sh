#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts/macos
xcrun swiftc -O macos/TitleAXProbe.swift -o artifacts/macos/TitleAXProbe -framework AppKit -framework ApplicationServices
echo 'BUILT artifacts/macos/TitleAXProbe (no auto-run)'
