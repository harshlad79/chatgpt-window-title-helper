#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ChatGPTTitleOverlay"
BUNDLE_ID="local.chatgpt.titleoverlay"
SIGNING_IDENTITY="EBC7B73928C50D22D965AFE909AB5CBD519FB851"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
APP="$HOME/Applications/$APP_NAME.app"
if [ -n "$(printenv APP_PATH 2>/dev/null || :)" ]; then
    APP="$APP_PATH"
fi

case "$APP" in /*) ;; *) echo "ERROR: APP_PATH must be absolute" >&2; exit 3 ;; esac
test -d "$APP/Contents/MacOS" || {
    echo "ERROR: No existing $APP_NAME.app found; refusing to create one" >&2
    exit 3
}
actual_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$actual_id" != "$BUNDLE_ID" ]; then
    echo "ERROR: Unexpected Bundle ID $actual_id" >&2; exit 4
fi
if pgrep -x "$APP_NAME" >/dev/null || pgrep -x ChatGPTTitleHelper >/dev/null; then
    echo "ERROR: Quit existing TitleOverlay or helper before updating" >&2
    exit 5
fi
if ! security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" |
    grep -F "$SIGNING_IDENTITY \"TheCompany\"" >/dev/null; then
    echo "ERROR: Stable TheCompany identity missing from login keychain" >&2; exit 6
fi

cd "$ROOT"
./macos/tests/run.sh
mkdir -p "$ROOT/artifacts/macos/backups"
stage_root="$(mktemp -d "$ROOT/artifacts/macos/.title-install.XXXXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
candidate="$stage_root/$APP_NAME.app"
ditto "$APP" "$candidate"
cp "$ROOT/artifacts/macos/ChatGPTTitleHelper" \
    "$candidate/Contents/MacOS/$APP_NAME"
chmod +x "$candidate/Contents/MacOS/$APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \
    "$candidate/Contents/Info.plist")" = "$BUNDLE_ID"
codesign --force --timestamp=none --keychain "$LOGIN_KEYCHAIN" \
    --sign "$SIGNING_IDENTITY" "$candidate"
codesign --verify --deep --strict --verbose=2 "$candidate"
codesign -dr - "$candidate" 2>&1

backup_dir="$(mktemp -d "$ROOT/artifacts/macos/backups/titleoverlay-before-event.XXXXXXXX")"
backup="$backup_dir/$APP_NAME.app"
mv "$APP" "$backup"
if ! mv "$candidate" "$APP"; then
    mv "$backup" "$APP"
    echo "ERROR: Install failed and original was restored" >&2
    exit 7
fi
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
    mv "$APP" "$stage_root/invalid.app"
    mv "$backup" "$APP"
    echo "ERROR: Verification failed and original was restored" >&2
    exit 8
fi
echo "INSTALLED_APP: $APP"
echo "BUNDLE_ID: $BUNDLE_ID"
echo "IDENTITY: $SIGNING_IDENTITY"
echo "ROLLBACK: $backup"
echo "WARNING: Accessibility may require one reapproval when switching ad-hoc to certificate signing"
