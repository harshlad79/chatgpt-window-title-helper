# ChatGPT Title Overlay for macOS

macOS menu-bar helper for exposing ChatGPT conversation titles outside the ChatGPT window.

It can display a non-activating title overlay and optionally synchronize the native/Dock window title.

## Requirements

- macOS on Apple Silicon (arm64) for the currently verified build.
- ChatGPT desktop app.
- Xcode Command Line Tools with `xcrun swiftc`.
- Accessibility permission for ChatGPT Title Overlay.
- The current target ChatGPT bundle identifier is `com.openai.codex`.

### Verified build environment

The current source was built and tested with:

- Architecture: Apple Silicon (`arm64`)
- Swift: 6.4
- Xcode Command Line Tools: 27.0
- Compiler target observed during development: `arm64-apple-macosx26.0`

The exact macOS point release used during development was not recorded. The values above describe the build environment that was actually verified, not a guaranteed minimum requirement.

## Build and install

From the repository:

```bash
cd macos
chmod +x build.sh
./build.sh
```

`build.sh` performs the complete local build/install cycle:

1. Stops a previously running `ChatGPTTitleOverlay` process.
2. Creates or updates the app bundle at `~/Applications/ChatGPTTitleOverlay.app`.
3. Generates `Info.plist`.
4. Compiles `ChatGPTTitleOverlay.swift` with `xcrun swiftc`.
5. Applies ad-hoc code signing with `codesign --sign -`.
6. Launches the installed app.

There is no separate copy/install step after running the script.

Installed app:

```text
~/Applications/ChatGPTTitleOverlay.app
```

## Accessibility permission

The helper reads the ChatGPT Accessibility tree, so macOS Accessibility permission is required.

After the first build/launch:

1. Open **System Settings**.
2. Open **Privacy & Security**.
3. Open **Accessibility**.
4. Enable **ChatGPT Title Overlay**.
5. If macOS asks you to quit/reopen the helper, do so.

If the helper is not listed, add:

```text
~/Applications/ChatGPTTitleOverlay.app
```

to the Accessibility list manually.

### Rebuild / TCC permission issue

The current build script uses ad-hoc signing. After rebuilding, macOS may still show the previous Accessibility entry as enabled while the newly built app is not actually trusted.

If title detection stops working after a rebuild:

1. Remove **ChatGPT Title Overlay** from **System Settings → Privacy & Security → Accessibility**.
2. Run `./build.sh` again if necessary.
3. Add/enable the newly built app in Accessibility again.
4. Relaunch the helper.

A stable Developer ID signature and notarization would avoid this class of identity problem for a packaged public binary. This repository currently provides a source/local build instead.

## Usage

After launch, the helper runs as a menu-bar app and does not appear as a normal Dock application.

Use the **T** menu-bar item to control:

- Screen overlay
- Dock/native window title synchronization
- Accessibility settings
- Exit

The overlay and native-title synchronization can be enabled independently.

The helper reads the active conversation title from the ChatGPT desktop app Accessibility tree, using the descendant `AXWebArea` title.

### Native/Dock title synchronization

Changing the renderer `document.title` alone does not reliably update the native ChatGPT window/Dock title.

For native synchronization, the helper:

1. Finds the running ChatGPT desktop process.
2. Enables the Electron main-process inspector with `SIGUSR1` when needed.
3. Connects to the local inspector endpoint.
4. Matches Electron `BrowserWindow` instances to ChatGPT windows.
5. Calls `BrowserWindow.setTitle()`.

ChatGPT can therefore be launched normally; no special ChatGPT launch command is required.

The inspector is expected on localhost (`127.0.0.1`) and is used only for the optional native-title synchronization feature.

## Known limitations

- The implementation depends on internal details of the ChatGPT desktop app and may require updates after ChatGPT app changes.
- It currently targets the ChatGPT bundle identifier `com.openai.codex`.
- Accessibility permission is required for conversation-title discovery.
- Native-title synchronization depends on Electron main-process inspector behavior.
- The current build is ad-hoc signed, not Developer ID signed or notarized.
- The currently verified build environment is Apple Silicon/arm64; other architectures have not been verified.
- Generic/new ChatGPT surfaces whose title is simply `ChatGPT` are not treated as conversation titles for native synchronization.

## Files

- `ChatGPTTitleOverlay.swift` — application source.
- `build.sh` — local build, app-bundle creation, ad-hoc signing, installation, and launch.
