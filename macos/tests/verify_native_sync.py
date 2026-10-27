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
