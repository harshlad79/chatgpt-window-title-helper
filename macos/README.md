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
