#!/usr/bin/env python3
"""Prove event-driven source retains the original NativeTitleSync verbatim."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
old = (root / "macos/legacy/ChatGPTTitleOverlay.swift").read_text()
new = (root / "macos/ChatGPTTitleHelper.swift").read_text()
begin = "final class NativeTitleSync {"
end = "// ============================================================\n// Controller"
def extract(source):
    return source.split(begin, 1)[1].split(end, 1)[0]

assert extract(old) == extract(new), "NativeTitleSync changed"
assert 'private let refreshInterval: TimeInterval = 0.5' in old
assert 'private let refreshInterval: TimeInterval = 2.0' in new
assert 'MacAXTitleObserver(pid: pid' in new
assert 'titleRetryPlan = TitleRevisionRetryPlan()' in new
assert 'titleRetryPlan.retainOnly(ids)' in new
assert 'titleRetryPlan.complete(selectedID)' in new
assert 'requestOneOverdue(visibleIDs, now: Date())' in new
assert 'if allowBackgroundFallback {' in new
assert 'self.refresh(allowBackgroundFallback: false)' in new
assert 'titleScheduler.pop()' in new
assert 'findConversationTitleButtons' in new
assert 'buttons: buttons' in new
assert 'NativeTitleSync()' in new
assert 'nativeSync.sync(pid: pid, windows: windows)' in new
# Simulate Swift conditional compilation in the normal (no -D) build.
# The legacy implementation is intentionally present but cannot be reached
# from any active menu, quit, or refresh path in the safe release.
def default_compiled_text(source):
    enabled = [True]
    output = []
    for line in source.splitlines():
        directive = line.strip()
        if directive == "#if TITLEHELPER_NATIVE_WRITER_VERIFIED":
            enabled.append(enabled[-1] and False)
        elif directive == "#if !TITLEHELPER_NATIVE_WRITER_VERIFIED":
            enabled.append(enabled[-1] and True)
        elif directive == "#else":
            assert len(enabled) > 1
            parent = enabled[-2]
            enabled[-1] = parent and not enabled[-1]
        elif directive == "#endif":
            assert len(enabled) > 1
            enabled.pop()
        elif enabled[-1]:
            output.append(line)
    assert len(enabled) == 1
    return "\\n".join(output)

active = default_compiled_text(new)
assert "nativeSync.sync(" not in active
assert "nativeSync.restore(" not in active
assert "TITLEHELPER_NATIVE_WRITER_VERIFIED" not in (
    root / "macos/build-title-helper.sh").read_text()
assert new.count('#if TITLEHELPER_NATIVE_WRITER_VERIFIED') == 2
assert new.count('#if !TITLEHELPER_NATIVE_WRITER_VERIFIED') == 1
assert 'native-sync-blocked source=quit' in new
assert 'native-sync-blocked source=menu' in new
assert 'Dock: 안전 중지 (Inspector 미검증)' in new
# New safety comments may refer to a signal; the original implementation,
# including actual signal calls, must remain IDENTICAL.
assert extract(old).count('SIGUSR1') == extract(new).count('SIGUSR1')
print("PASS unchanged NativeTitleSync and event-driven wiring")

assert 'dockSidecar.start()' in new
assert 'dockSidecar.update(sidecarEntries)' in new
assert 'dockSidecar.stop()' in new
assert 'NativeTitleSync()' in new

assert 'WindowSessionHistoryStore()' in new
assert 'DockRecentWindowRestorer()' in new
assert 'sessionHistory.observe(' in new
assert 'recentRestorer.restore(title: title)' in new
assert 'restoreQueue.start(' in new
assert 'dockSidecar.onRestoreAll' in new
assert 'restoreProgress.onCancel' in new
assert 'sessionHistory.lastSessionTargets(pid: currentPID)' in new
assert 'sessionHistory.recoverable(excluding: [], pid: pid)' in new

assert 'Its own AXMenu is sufficient evidence' in Path('macos/DockMenuSidecar.swift').read_text()

assert 'lastAXWindowCensusSucceeded' in new
# A recognized-title count of zero must not masquerade as zero native windows.
assert 'ax-window-census' in new
assert 'available raw=' in new and 'recognized=' in new
assert 'nativeGeneric=' in new and 'nativeNamed=' in new
assert 'nativeEmpty=' in new and 'standard=' in new and 'minimized=' in new
assert 'matchedSaved=' in new and 'minimizedSaved=' in new
assert 'matchedPrevious=' in new and 'matchedRecent=' in new
# Minimized windows must be probed read-only, once per PID, off the UI loop.
assert 'boundedMinimizedWebAreaTitle' in new
assert 'minimizedAXProbePID' in new
assert 'DispatchQueue.global(qos: .utility).async' in new
assert 'ax-minimized-webarea pid=' in new
assert 'index < 48' in new
assert 'AXUIElementSetMessagingTimeout(element, 0.2)' in new
assert 'Set(sessionHistory.snapshot.previousSessionOpen)' in new
assert 'Set(sessionHistory.snapshot.recentTitles)' in new
# Direct minimized-window metadata must be read-only, bounded and aggregate-only.
assert 'axWindowMetadataText' in new
assert 'axWindowMetadataText(window, "AXDocument")' in new
assert 'axWindowMetadataText(window, "AXURL")' in new
assert 'axWindowMetadataText(window, "AXIdentifier")' in new
assert 'ax-minimized-metadata pid=' in new
assert 'uniqueDocument=' in new and 'uniqueURL=' in new
assert 'uniqueIdentifier=' in new
assert 'for window in raw.prefix(8)' in new
assert 'AXUIElementSetAttributeValue(window, "AXDocument"' not in new

# Already-visible web areas can expose identity without touching minimized owner windows.
assert 'lastVisibleIdentityProbeCount' in new
assert 'sidecarEntries.prefix(8).compactMap' in new
assert 'ax-visible-identity pid=' in new
assert 'axWindowMetadataText(area, "AXURL")' in new
assert 'axWindowMetadataText(area, "AXDocument")' in new
assert 'axWindowMetadataText(area, "AXIdentifier")' in new
assert 'axWindowMetadataText(area, "AXDOMIdentifier")' in new
assert 'nativeEqualsWeb=' in new and 'chatPath=' in new
assert 'samples.count' in new
assert 'webURLPresent=' in new and 'webURLChatGPTHost=' in new
assert 'webURLChatGPTRoot=' in new and 'webURLChatGPTConversationPath=' in new
assert 'webURLOtherHTTPHost=' in new and 'webURLNonHTTP=' in new
assert 'webURLUnparsed=' in new
assert 'URLComponents(string: webURL)' in new
assert 'webURLPresent += 1' in new
assert 'webURLs.insert(webURL)' in new
assert 'AXUIElementSetAttributeValue(area' not in new

# Share/copy-link discovery must remain read-only and bounded.
assert 'boundedShareControlCensus' in new
assert 'index < 96' in new
assert 'ProcessInfo.processInfo.systemUptime - started < 2.0' in new
assert 'shareCandidates=' in new and 'copyLinkCandidates=' in new
assert 'shareNodesVisited=' in new and 'shareScanLimited=' in new
assert 'boundedShareControlCensus(area)' in new
assert 'axString(element, kAXDescriptionAttribute)' in new
assert 'axString(element, kAXHelpAttribute)' in new
assert 'AXUIElementSetMessagingTimeout(element, 0.15)' in new
assert 'AXUIElementCopyActionNames(element, &rawActions)' in new
assert 'axBool(element, kAXEnabledAttribute) == true' in new
assert 'shareEnabled=' in new and 'sharePressable=' in new
assert 'shareActionable=' in new and 'shareMenuRole=' in new
assert 'copyLinkEnabled=' in new and 'copyLinkPressable=' in new
assert 'if enabled && hasPress { shareActionable += 1 }' in new
# Non-public-share navigation affordance from installed ChatGPT app bundle.
# Only AXLink/AXMenuItem metadata is inspected; no owner UI interaction.
assert 'openOnChatGPTControls=' in new
assert 'openOnChatGPTConversationURLs=' in new
assert 'role == "AXLink" || role == "AXMenuItem"' in new
assert 'label.contains("open on chatgpt.com")' in new
assert 'parsed.path.hasPrefix("/c/")' in new
assert 'axWindowMetadataText(element, "AXURL")' in new
assert 'AXUIElementPerformAction(element' not in new

assert 'Set(sessionHistory.lastSessionTargets(pid: pid))' in new
assert 'lastAXCensusLogState = nil' in new
assert 'dockSidecar.updateHistory([])' in new
assert 'let complete = lastAXWindowCensusSucceeded &&' in new

assert 'sessionHistory.hasPendingRestart(pid: pid)' in new
assert 'history-restart-pending pid=' in new
assert 'prepareForegroundRestore' in new
assert 'freshOpenConversationTitles' in new
assert 'history-restore-blocked reason=foreground-AX-incomplete' in new

# One-shot blank-window probe is opt-in and cannot navigate an owner chat.
restorer = Path('macos/DockRecentWindowRestorer.swift').read_text()
assert 'TITLEHELPER_SAFE_BLANK_PROBE' in new
assert 'self.recentRestorer.probeBlankWindow' in new
assert 'func probeBlankWindow(' in restorer
assert 'originalIDs.count == original.count' in restorer
assert 'originalMinimized' in restorer
assert 'after.count == original.count + 1' in restorer
assert 'created.count == 1 && originalsRetained' in restorer
assert 'priorFrontmost.activate()' in restorer
assert 'probeBlankWindow(completed:' in restorer

# Dock Recent restore must use the same focus/creation safety proven by
# the live blank-window E2E; do not press the menu immediately after activate.
restore = restorer.split('    func restore(title: String,', 1)[1]
assert 'frontmostApplication?.processIdentifier' in restore
assert 'let newWindowMenu = self.fileNewWindow(root)' in restore
assert 'self.press(newWindowMenu)' in restore
assert 'func waitForNewWindow()' in restore
assert 'elapsed < 8.0' in restore
assert 'originalsRetained' in restore
assert 'originalMinimized' in restore
assert restore.index('frontmostApplication?.processIdentifier') < restore.index('self.press(newWindowMenu)')
assert restore.index('func waitForNewWindow()') < restore.index('self.dockRecentMatches(title)')

# Search UI diagnostic is opt-in, creates a fresh window, and never types,
# selects a result, or navigates a saved owner conversation.
assert 'TITLEHELPER_SAFE_SEARCH_UI_PROBE' in new
assert 'self.recentRestorer.probeSearchUI' in new
assert 'func probeSearchUI(completed:' in restorer
assert 'private func probeSearchOnNewWindow(' in restorer
assert 'newWindowFocused()' in restorer
assert 'originalsSafe()' in restorer
assert 'search-button-count=' in restorer
assert 'self.press(scan.buttons[0])' in restorer
assert 'search-UI-only opened=' in restorer
# Search AX hierarchy traversal must have a wall-clock/monotonic deadline only.
# Never truncate a large Chromium AX tree by total node or per-parent count.
search_scan = restorer.split('    private func searchUIScan(', 1)[1].split('    private func probeSearchOnNewWindow(', 1)[0]
assert 'ProcessInfo.processInfo.systemUptime - started < 3.0' in search_scan
assert 'queue.append(contentsOf: next)' in search_scan
assert 'index < 800' not in search_scan
assert 'next.prefix(' not in search_scan
assert 'index >= 800' not in search_scan
assert 'let timedOut = index < queue.count &&' in search_scan
search_probe = restorer.split('    func probeSearchUI(completed:', 1)[1].split('    func restore(title:', 1)[0]
assert 'fileNewWindow(root)' in search_probe
assert 'self.probeSearchOnNewWindow(' in search_probe
assert 'dockRecentMatches(' not in search_probe
assert 'AXUIElementSetAttributeValue' not in search_probe
assert 'setValue(' not in search_probe
assert 'typeText' not in search_probe
