#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/macos/build-probe.sh"
# Never invent an application directory. Update only an existing app.
APP_PATH="$(printenv APP_PATH 2>/dev/null || true)"
if [ -n "$APP_PATH" ]; then
    APP="$APP_PATH"
else
    APP=""
    for candidate in "$HOME/Applications/ChatGPTTitleProbe.app" "$HOME/응용 프로그램/ChatGPTTitleProbe.app"; do
        if [ -d "$candidate" ]; then
            if [ -n "$APP" ]; then
                echo "ERROR: Multiple installed probe apps; set APP_PATH explicitly" >&2
                exit 3
            fi
            APP="$candidate"
        fi
    done
fi
if [ -z "$APP" ] || [ ! -d "$APP/Contents/MacOS" ]; then
    echo "ERROR: Existing ChatGPTTitleProbe.app not found; set APP_PATH" >&2
    exit 3
fi
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
