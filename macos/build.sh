#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APP_NAME="ChatGPTTitleOverlay"
APP="$HOME/Applications/$APP_NAME.app"

SRC="$SCRIPT_DIR/$APP_NAME.swift"

CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
BINARY="$MACOS/$APP_NAME"
PLIST="$CONTENTS/Info.plist"

BUNDLE_ID="local.chatgpt.titleoverlay"

# ------------------------------------------------------------
# Check source
# ------------------------------------------------------------

if [ ! -f "$SRC" ]; then
    echo "ERROR: $APP_NAME.swift not found"
    echo "$SRC"
    exit 1
fi

# ------------------------------------------------------------
# Stop previous version
# ------------------------------------------------------------

echo "[1/6] 기존 프로세스 종료"

pkill -x "$APP_NAME" 2>/dev/null || true

sleep 0.3

# ------------------------------------------------------------
# Create app bundle
# ------------------------------------------------------------

echo "[2/6] 앱 번들 준비"

mkdir -p "$HOME/Applications"
mkdir -p "$MACOS"

# ------------------------------------------------------------
# Info.plist
# ------------------------------------------------------------

echo "[3/6] Info.plist 생성"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
"-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>ChatGPT Title Overlay</string>

    <key>CFBundleDisplayName</key>
    <string>ChatGPT Title Overlay</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <!-- Dock에 표시하지 않고 메뉴바 앱으로 동작 -->
    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>

</dict>
</plist>
PLIST

# ------------------------------------------------------------
# Compile
# ------------------------------------------------------------

echo "[4/6] Swift 컴파일"

xcrun swiftc \
    "$SRC" \
    -o "$BINARY" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework QuartzCore

chmod +x "$BINARY"

# ------------------------------------------------------------
# Sign
# ------------------------------------------------------------

echo "[5/6] 앱 서명"

codesign \
    --force \
    --deep \
    --sign - \
    "$APP"

# ------------------------------------------------------------
# Launch
# ------------------------------------------------------------

echo "[6/6] 실행"

open "$APP"

echo
echo "=========================================="
echo "BUILD OK"
echo "$APP"
echo "=========================================="