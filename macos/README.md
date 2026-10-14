# Mac ChatGPT Window Title Helper — compatibility workstream

Windows canonical: main Windows implementation in this repository.
Mac source: exact copy from an existing local unversioned September 2026
Swift project, preserved under legacy/.

Not yet safe to deploy on the current com.openai.codex application:
- Original Swift overlay rescans all AX windows every 0.5 seconds on main thread.
- Its native title path assumes Electron BrowserWindow + inspector, attempts
  SIGUSR1 on the ChatGPT PID when inspector is missing.
- Current macOS ChatGPT implementation and title setter compatibility unverified.
- The Mac Dev node-agent returned AXIsProcessTrusted=false and -25211
  for AXWindows, so live UIA/AX element observation requires user approval.

Safe research probe: TitleAXProbe.swift. Builds using build-probe.sh.
It reads native/window and webarea titles, checks whether native AXTitle is
settable WITHOUT modifying the window, and optionally observes AX title/value
changes for up to 900 seconds. No SIGUSR1 or inspector use.
The probe requires Accessibility permission to read the ChatGPT AX tree.
Do not commit output logs containing private conversation titles.

Next implementation gate: identify reliable macOS title change notifications
and supported native title update path; then implement serial prioritized AX
polling with one overdue window per discovery tick. Do not silently substitute
legacy Electron code for the Windows implementation.

To prepare the separately permissioned, read-only native app:
  ./macos/package-probe.sh
This creates ~/Applications/ChatGPTTitleProbe.app but does NOT open it.
macOS System Settings > Privacy & Security > Accessibility: add and allow
ChatGPTTitleProbe.app. Opening the app after permission starts a 15-minute AX
observation. Its diagnostic log is in ~/Library/Logs/ChatGPTTitleHelper/title-ax-probe-current.log.
Do not upload or commit this log: it may contain private conversation titles. If access is denied, the probe exits without changing
ChatGPT. Packaging uses the existing 2036 TheCompany certificate, not ad-hoc signing. The initial change from ad-hoc may require one reauthorization; verify TCC after subsequent updates.

## October 15 — v2 AX tree probe

Actual macOS ChatGPT accessibility: v1 observed three AXWindows with
read-only AXTitle, and no AXWebArea. AXWindow title events did not fire on
the observed rename. The v2 probe scans up to 1,000 internal nodes, logs
roles/hashes/lengths rather than conversation text, subscribes to title,
value, selected children, and layout changes on candidate elements, and
rescans every 12 seconds to detect changes even without notifications.

The v2 executable compiled and the preexisting app was re-signed once.
This changed its ad-hoc signature identity, and the first run returned
AXIsProcessTrusted=false. Needs Accessibility reauthorization before
further live investigation. Do not re-sign again during the next run.

The packaging script only replaces an explicitly selected/already existing
app bundle; it no longer creates a separate ~/Applications folder.
Use APP_PATH for a nonstandard location. No changes to the legacy overlay.

## Persistent code signing (2026-10-15)

The canonical cross-project rule is thecompany-core/docs/operations/macos-app-signing-identity.md.
The tested local signing procedure is documented at
thecompany-browser/docs/operations/macos-local-code-signing.md.
The existing TheCompany login Keychain code-signing identity (public SHA-1
EBC7B73928C50D22D965AFE909AB5CBD519FB851, expires 2036) is reused.
Do not choose TheCompany Local Signing Test 2026, create a new certificate,
or sign ChatGPTTitleProbe ad-hoc. Its Bundle ID stays local.chatgpt.titleprobe.

The packaging script must find the existing installed app (or use explicit
APP_PATH); it will not create a new Applications directory. It preserves the
previous app under ignored artifacts/macos/backups, builds and signs a staged
candidate once, verifies the code-signing requirement, and installs it.
The certificate and its private key stay in the login Keychain; never commit
private keys, binary bundles or secrets to GitHub.

The transition from an ad-hoc signature to the stable certificate can require
one macOS Accessibility reapproval. A stable DR across further builds is
necessary but does not itself prove TCC authorization retention; check it on
the Mac. Keychain may display a private-key approval dialog during codesign;
the user must approve it rather than attempting to automate the dialog.

## October 15 — live AX discovery after consent

macos-main ChatGPT process 37140 (macOS 26.6.2, com.openai.codex),
signed TitleProbe under stable TheCompany 2036 identity. Probe v2 successfully
read three windows but only 12 AX nodes each. The earlier AXTitleChanged
window-only subscriptions produced no events during the user's first rename.

The v3-v5 probes also inspect AXFocusedUIElement and alternative AX child
attributes (AXVisibleChildren, AXContents, AXChildrenInNavigationOrder),
and report fingerprints only (role / length / truncated SHA-256).
The original overlay enabled AXEnhancedUserInterface. On this Mac it returned
-25208, while a follow-up read yielded true. The official Electron macOS
AXManualAccessibility request returned -25205 (unsupported) on this build.
Do not claim AXManualAccessibility was responsible for discovery.

After the accessibility tree became available, the focused element yielded
a large subtree including 20 AXHeading nodes. In v5, two other windows also
showed AXWebArea; v5 logs baseline fingerprints for 17 distinct heading, static
text and button candidates and deltas at 12-second intervals. A controlled
user rename is still required to determine the **actual** conversation title
element and whether AXTitleChanged / AXValueChanged is delivered. Do not
infer event reliability from successful subscriptions.

Each subsequent signed app update under the same certificate and stable
Bundle ID kept AXIsProcessTrusted true without new consent (actual live
observations). Keep using stable certificate signing and explicit app
path. Never run the legacy Electron inspector signal in diagnosis.

Official Electron accessibility guidance:
https://www.electronjs.org/docs/latest/tutorial/accessibility
