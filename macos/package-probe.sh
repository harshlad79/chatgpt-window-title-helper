#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ChatGPTTitleProbe"
BUNDLE_ID="local.chatgpt.titleprobe"
# Public fingerprint for the pre-existing 2036 TheCompany signing identity.
# Never substitute the similarly named, short-lived experimental certificate.
SIGNING_IDENTITY="EBC7B73928C50D22D965AFE909AB5CBD519FB851"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Reuse the actual installed app's location; never create ~/Applications.
if [ -n "$(printenv APP_PATH 2>/dev/null || true)" ]; then
    APP="$APP_PATH"
else
    APP=""
    for candidate in "$HOME/Applications/$APP_NAME.app" "$HOME/응용 프로그램/$APP_NAME.app"; do
        if [ -d "$candidate" ]; then
            if [ -n "$APP" ]; then
                echo "ERROR: Multiple installed apps; set APP_PATH explicitly" >&2
                exit 3
            fi
            APP="$candidate"
        fi
    done
fi

if [ -z "$APP" ] || [ ! -d "$APP/Contents/MacOS" ]; then
    echo "ERROR: Existing $APP_NAME.app not found; set APP_PATH" >&2
    exit 3
fi
case "$APP" in /*) ;; *) echo "ERROR: APP_PATH must be absolute" >&2; exit 3 ;; esac
actual_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [ "$actual_id" != "$BUNDLE_ID" ]; then
    echo "ERROR: Bundle ID mismatch: $actual_id" >&2
    exit 4
fi
if pgrep -f '/ChatGPTTitleProbe.app/Contents/MacOS/ChatGPTTitleProbe' >/dev/null; then
    echo "ERROR: Quit running $APP_NAME before updating" >&2
    exit 5
fi

# The stable identity must be a valid code-signing identity in the login keychain.
identities="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN")"
if ! printf '%s\n' "$identities" | grep -F "$SIGNING_IDENTITY \"TheCompany\"" >/dev/null; then
    echo "ERROR: 2036 TheCompany code-signing identity unavailable in login keychain" >&2
    exit 6
fi

cd "$ROOT"
"$ROOT/macos/build-probe.sh"
mkdir -p "$ROOT/artifacts/macos/backups"
stage_root="$(mktemp -d "$ROOT/artifacts/macos/.probe-sign.XXXXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
staged="$stage_root/$APP_NAME.app"
ditto "$APP" "$staged"
cp "$ROOT/artifacts/macos/TitleAXProbe" "$staged/Contents/MacOS/$APP_NAME"
chmod +x "$staged/Contents/MacOS/$APP_NAME"

# Single certificate-based signing operation; no ad-hoc fallback.
codesign --force --timestamp=none --keychain "$LOGIN_KEYCHAIN" \
    --sign "$SIGNING_IDENTITY" "$staged"
codesign --verify --deep --strict --verbose=2 "$staged"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$staged/Contents/Info.plist" |
    grep -Fx "$BUNDLE_ID" >/dev/null
codesign -dr - "$staged" 2>&1

backup_root="$(mktemp -d "$ROOT/artifacts/macos/backups/probe-pre-cert.XXXXXXXX")"
backup="$backup_root/$APP_NAME.app"
mv "$APP" "$backup"
if ! mv "$staged" "$APP"; then
    mv "$backup" "$APP"
    echo "ERROR: Install failed; restored prior app" >&2
    exit 7
fi
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
    mv "$APP" "$stage_root/failed.app"
    mv "$backup" "$APP"
    echo "ERROR: Signature invalid after install; restored prior app" >&2
    exit 8
fi
echo "CERT_SIGNED: $APP"
echo "BUNDLE_ID: $BUNDLE_ID"
echo "SIGNING_IDENTITY: $SIGNING_IDENTITY"
echo "ROLLBACK_COPY: $backup"
echo "Accessibility may need one reauthorization when transitioning from ad-hoc."
