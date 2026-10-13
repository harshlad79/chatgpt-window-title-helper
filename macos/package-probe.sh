#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/macos/build-probe.sh"
APP="$HOME/Applications/ChatGPTTitleProbe.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/artifacts/macos/TitleAXProbe" "$APP/Contents/MacOS/ChatGPTTitleProbe"
chmod +x "$APP/Contents/MacOS/ChatGPTTitleProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChatGPTTitleProbe</string>
<key>CFBundleIdentifier</key><string>local.chatgpt.titleprobe</string>
<key>CFBundleName</key><string>ChatGPT Title Probe</string>
<key>CFBundleDisplayName</key><string>ChatGPT Title Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "PACKAGED: $APP"
echo "NOT LAUNCHED: authorize in Accessibility first"
