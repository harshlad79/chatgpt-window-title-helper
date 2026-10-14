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
ChatGPT. Repacking with ad hoc signing may reset permission.

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
