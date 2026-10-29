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
share_scan = new.split('private func boundedShareControlCensus(', 1)[1].split('// Read-only observation can safely subscribe', 1)[0]
assert 'index < 96' not in share_scan
assert 'children.prefix(12)' not in share_scan
assert 'while index < queue.count &&' in share_scan
assert 'ProcessInfo.processInfo.systemUptime - started < 2.0' in share_scan
assert 'queue.append(contentsOf: children)' in share_scan
assert 'queue.count - index, index < queue.count' in share_scan
assert 'shareScanElapsedMs=' in new and 'shareScanRemaining=' in new
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
assert 'ProcessInfo.processInfo.systemUptime - started < 5.0' in search_scan
assert 'let timedOut = index < queue.count && elapsed >= 5.0' in search_scan
assert 'queue.append(contentsOf: next)' in search_scan
assert 'index < 800' not in search_scan
assert 'next.prefix(' not in search_scan
assert 'index >= 800' not in search_scan
assert 'let timedOut = index < queue.count &&' in search_scan
# No-click focused-window Search scan measurement: no new native window,
# AX mutation, user content, or unbounded node-count cap.
assert 'TITLEHELPER_SAFE_FOCUSED_SEARCH_METRICS' in new
assert 'self.recentRestorer.probeFocusedSearchMetrics' in new
assert 'focused-search-metrics success=' in new
assert 'func probeFocusedSearchMetrics(' in restorer
assert 'visited.count, Int(elapsed * 1000), queue.count - index' in search_scan
assert 'remainingCount: Int' in search_scan
metrics_probe = restorer.split('    func probeFocusedSearchMetrics(', 1)[1].split('    private func probeSearchOnNewWindow(', 1)[0]
assert 'kAXFocusedWindowAttribute' in metrics_probe
assert 'kAXFocusedUIElementAttribute' in metrics_probe
assert 'searchUIScan(focused)' in metrics_probe
assert 'windowsPreserved=' in metrics_probe
assert 'timedOut=' in metrics_probe and 'elapsedMs=' in metrics_probe
assert 'fileNewWindow(' not in metrics_probe
assert 'self.press(' not in metrics_probe
assert 'AXUIElementSetAttributeValue' not in metrics_probe
assert 'app.activate()' not in metrics_probe
# Read-only ownership evidence: distinguish generic/named focused window,
# parent AXWindow linkage and AXWindow identity without reading private labels.
assert 'nativeKind=' in metrics_probe and 'genericWindows=' in metrics_probe
assert 'focusedIndex=' in metrics_probe and 'minimizedWindows=' in metrics_probe
assert 'kAXWindowAttribute' in metrics_probe
assert 'kAXParentAttribute' in metrics_probe
assert 'parentWindowMatched=' in metrics_probe
assert 'uiWindowMatched=' in metrics_probe
assert 'AXUIElementSetMessagingTimeout(current, 0.2)' in metrics_probe
assert 'while focusedParentDepth < 24' in metrics_probe
assert 'kAXValueAttribute' not in metrics_probe
assert 'AXUIElementPerformAction' not in metrics_probe
assert 'AXUIElementSetAttributeValue' not in metrics_probe
# Visible conversation AXURL was non-HTTP and non-unique; record only
# aggregate scheme/path shape, never full URL, path, or chat identifier.
assert 'webURLAppScheme=' in new and 'webURLChatGPTScheme=' in new
assert 'webURLNonHTTPConversationPath=' in new
# Opt-in common app-origin readback is permitted only for static identical URLs.
assert 'TITLEHELPER_SAFE_COMMON_APP_AXURL' in new
assert 'webURLPresent == samples.count' in new
assert 'webURLs.count == 1' in new
assert 'parsed.query == nil, parsed.fragment == nil' in new
assert 'ax-common-app-url blocked=not-static-common' in new
assert 'if scheme == "app"' in new and 'if scheme == "chatgpt"' in new
assert 'if parsed.path.contains("/c/")' in new

search_probe = restorer.split('    func probeSearchUI(completed:', 1)[1].split('    func restore(title:', 1)[0]
assert 'fileNewWindow(root)' in search_probe
assert 'self.probeSearchOnNewWindow(' in search_probe
assert 'dockRecentMatches(' not in search_probe
assert 'AXUIElementSetAttributeValue' not in search_probe
assert 'setValue(' not in search_probe
assert 'typeText' not in search_probe

# Isolated Search input capability check: read-only, identity-fenced, no text entry.
assert 'TITLEHELPER_SAFE_ISOLATED_INPUT_CAPABILITIES' in new
assert 'self.recentRestorer.probeIsolatedSearchInputCapabilities(' in new
assert 'isolated-input-capabilities success=' in new
input_probe = restorer.split('    func probeIsolatedSearchInputCapabilities(', 1)[1].split(
    '    // Explicit one-shot Search query', 1)[0]
assert 'expected.count == 8' in input_probe
assert 'before == expected' in input_probe and 'after == expected' in input_probe
assert 'String(CFHash($0)) == expectedID' in input_probe
assert 'AXUIElementIsAttributeSettable' in input_probe
assert 'inputCount == 1' in input_probe
assert 'originalsPreserved=' in input_probe
for forbidden in ['AXUIElementPerformAction', 'AXUIElementSetAttributeValue',
                  'fileNewWindow(', 'app.activate(', 'dockRecentMatches(',
                  'press(', 'NSLog(', 'print(']:
    assert forbidden not in input_probe, forbidden

# Isolated fixed-query write is opt-in, baseline/focus/empty-input fenced.
assert 'TITLEHELPER_SAFE_ISOLATED_SEARCH_QUERY' in new
assert 'self.recentRestorer.probeIsolatedSearchQuery(' in new
assert 'isolated-search-query success=' in new
query_probe = restorer.split('    func probeIsolatedSearchQuery(', 1)[1].split(
    '    // One-shot, strictly read-only diagnosis', 1)[0]
for required in ['expected.count == 8', 'expected[expectedID] == false',
                 'expected.values.filter({ $0 }).count == 3',
                 'before == expected', 'snapshot().0 == expected',
                 'String(CFHash(focused as! AXUIElement)) == expectedID',
                 'inputs.count == 1', 'kAXValueAttribute', '== ""',
                 'AXUIElementIsAttributeSettable', 'AXUIElementSetAttributeValue',
                 '"ChatGPT" as NSString', 'DispatchQueue.main.asyncAfter',
                 'self.probeIsolatedSearchResultMetadata(',
                 'originalsPreserved=', 'AXValueReadback=']:
    assert required in query_probe, required
for forbidden in ['fileNewWindow(', 'dockRecentMatches(', 'app.activate(',
                  'AXUIElementPerformAction', 'NSLog(', 'print(',
                  'sendMessage(', 'typeText(']:
    assert forbidden not in query_probe, forbidden

# Isolated result metadata probe: privacy-safe, read-only, identity-fenced.
assert 'TITLEHELPER_SAFE_ISOLATED_RESULT_METADATA' in new
assert 'self.recentRestorer.probeIsolatedSearchResultMetadata(' in new
assert 'isolated-result-metadata success=' in new
metadata_probe = restorer.split('    func probeIsolatedSearchResultMetadata(', 1)[1].split(
    '    // Opt-in reversible contrast', 1)[0]
assert 'app.processIdentifier == expectedPID' in metadata_probe
assert 'expected.count == 8' in metadata_probe
assert 'before == expected' in metadata_probe and 'after == expected' in metadata_probe
assert 'String(CFHash($0)) == expectedID' in metadata_probe
assert 'AXUIElementCopyAttributeNames' in metadata_probe
assert 'AXValue' in metadata_probe and 'AXIdentifier' in metadata_probe and 'AXURL' in metadata_probe
assert 'uuidShaped=' in metadata_probe and 'chatURLShaped=' in metadata_probe
assert 'originalsPreserved=' in metadata_probe
for forbidden in ['AXUIElementPerformAction', 'AXUIElementSetAttributeValue',
                  'fileNewWindow(', 'app.activate(', 'dockRecentMatches(',
                  'press(', 'NSLog(', 'print(']:
    assert forbidden not in metadata_probe, forbidden

# Search-result role/action census: strict target-only read, no UI action.
assert 'TITLEHELPER_SAFE_ISOLATED_RESULT_ACTIONS' in new
assert 'self.recentRestorer.probeIsolatedSearchResultActions(' in new
assert 'isolated-result-actions success=' in new
result_actions_probe = restorer.split(
    '    func probeIsolatedSearchResultActions(', 1
)[1].split('    // Opt-in reversible contrast', 1)[0]
for required in ['expected.count == 8', 'expected[expectedID] == false',
                 'expected.values.filter({ $0 }).count == 3',
                 'before == expected', 'after == expected',
                 'String(CFHash($0)) == expectedID',
                 'AXUIElementCopyActionNames', 'kAXIdentifierAttribute',
                 'kAXURLAttribute', 'queryMatches == 1',
                 'originalsPreserved=', 'chatURLs=', 'pressable=',
                 'roleCounts=', 'pressRoles=', 'menuRoles=',
                 'listParents=', 'listChildren=', 'groupsInsideList=',
                 'pressGroupsInsideList=', 'menuGroupsInsideList=',
                 'pressGroupParents=', 'node.listIndex',
                 'listDetails=', 'listDirectRoles', 'listPressGroups',
                 'listTextNodes', 'listQueryTextNodes',
                 'listPressParentRoles',
                 'safeRoles.contains(role)', '"AXOption"', '"AXListBox"']:
    assert required in result_actions_probe, required
for forbidden in ['AXUIElementPerformAction', 'AXUIElementSetAttributeValue',
                  'fileNewWindow(', 'app.activate(', 'dockRecentMatches(',
                  'press(', 'NSLog(', 'print(']:
    assert forbidden not in result_actions_probe, forbidden

# Read-only, opt-in focus diagnostics distinguish baseline, foreground and
# target-focused conditions without pressing or exposing other window identities.
assert 'TITLEHELPER_SAFE_ISOLATED_FOCUS_DIAG' in new
assert 'self.recentRestorer.probeIsolatedFocusGate(' in new
assert 'isolated-focus-gate success=' in new
focus_diag = restorer.split('    func probeIsolatedFocusGate(', 1)[1].split(
    '    // Explicit one-shot Search UI press', 1)[0]
assert 'expected.count == 8' in focus_diag
assert 'actual == expected' not in focus_diag
assert 'before == expected' in focus_diag and 'after == expected' in focus_diag
assert 'kAXFocusedWindowAttribute' in focus_diag
assert 'chatgptFrontmost=' in focus_diag
assert 'focusedWindowAvailable=' in focus_diag
assert 'isolatedTargetFocused=' in focus_diag
assert 'originalsPreserved=true' in focus_diag
assert 'AXUIElementPerformAction' not in focus_diag
assert 'AXUIElementSetAttributeValue' not in focus_diag
assert 'fileNewWindow(' not in focus_diag
assert 'press(' not in focus_diag
assert 'app.activate()' not in focus_diag

# Combined isolated focus + Search contrast: no owner navigation or new window.
assert 'TITLEHELPER_SAFE_ISOLATED_FOCUS_CONTRAST' in new
assert 'self.recentRestorer.probeIsolatedFocusAndSearchContrast(' in new
assert 'isolated-focus-contrast success=' in new
combined_probe = restorer.split('    func probeIsolatedFocusAndSearchContrast(', 1)[1].split(
    '    // One-shot isolated-window AXRaise/restore preflight', 1)[0]
for required in [
    'expected.count == 8', 'expected[expectedID] == false',
    'expected.values.filter({ $0 }).count == 3',
    'before == expected', 'title(target) == "ChatGPT"',
    'originalID != expectedID', 'expected[originalID] == false',
    'kAXRaiseAction', 'probeIsolatedSearchContrast(',
    'mayRestoreFocus', 'originalFocusRestored', 'originalsPreserved=',
    'NSWorkspace.shared.frontmostApplication'
]:
    assert required in combined_probe, required
for forbidden in [
    'fileNewWindow(', 'dockRecentMatches(', 'app.activate(',
    'sendMessage(', 'typeText(', 'press(', 'AXUIElementSetAttributeValue',
    'NSLog(', 'print('
]:
    assert forbidden not in combined_probe, forbidden
assert 'func targetIdentitySafe() -> Bool' in contrast_probe
assert '(self.read(input, kAXValueAttribute) as? String) == noMatch' in contrast_probe
assert 'guard targetIdentitySafe(),' in contrast_probe
assert 'guard targetSafe(), noMatchReadback' not in contrast_probe

# Opt-in focus preflight may raise ONLY the known isolated generic window,
# then restore the original focus. It never types, navigates or closes windows.
assert 'TITLEHELPER_SAFE_ISOLATED_FOCUS_PREFLIGHT' in new
assert 'self.recentRestorer.probeIsolatedFocusPreflight(' in new
assert 'isolated-focus-preflight success=' in new
focus_preflight = restorer.split('    func probeIsolatedFocusPreflight(', 1)[1].rsplit(
    '\n}', 1)[0]
for required in [
    'expected.count == 8', 'expected[expectedID] == false',
    'expected.values.filter({ $0 }).count == 3',
    'before == expected', 'title(target) == "ChatGPT"',
    'originalID != expectedID', 'expected[originalID] == false',
    'kAXFocusedWindowAttribute',
    'AXUIElementPerformAction(\n            target, kAXRaiseAction as CFString',
    'AXUIElementPerformAction(original, kAXRaiseAction as CFString)',
    'NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID',
    'originalFocusRestored=', 'originalsPreserved=', 'restoreAttempted=',
]:
    assert required in focus_preflight, required
for forbidden in [
    'AXUIElementSetAttributeValue', 'fileNewWindow(',
    'dockRecentMatches(', 'press(', 'sendMessage(', 'typeText(',
    'app.activate(', 'NSLog(', 'print('
]:
    assert forbidden not in focus_preflight, forbidden

# One-shot activation is restricted to the previously focused isolated window;
# restore the prior foreground app only if ChatGPT still owns foreground.
assert 'TITLEHELPER_SAFE_ISOLATED_FOREGROUND_SEARCH' in new
assert 'self.recentRestorer.probeIsolatedForegroundSearch(' in new
assert 'isolated-foreground-search success=' in new
foreground_probe = restorer.split('    func probeIsolatedForegroundSearch(', 1)[1].split(
    '    // Explicit opt-in, read-only measurement', 1)[0]
assert 'expected.count == 8' in foreground_probe
assert 'expected[expectedID] == false' in foreground_probe
assert 'expected.values.filter({ $0 }).count == 3' in foreground_probe
assert 'actual == expected' in foreground_probe
assert 'targetFocused()' in foreground_probe
assert 'app.activate(options:' in foreground_probe
assert 'prior.activate(options:' in foreground_probe
assert 'self.probeIsolatedSearchPress(' in foreground_probe
assert 'NSWorkspace.shared.frontmostApplication?.processIdentifier ==' in foreground_probe
assert 'originalsPreserved=' in foreground_probe
assert 'priorFocusRestored=' in foreground_probe
assert 'fileNewWindow(' not in foreground_probe
assert 'AXUIElementPerformAction' not in foreground_probe
assert 'AXUIElementSetAttributeValue' not in foreground_probe
assert 'dockRecentMatches(' not in foreground_probe

# Isolated eighth-window Search press: fail closed on identity, PID and focus.
# It must not create a ninth window or navigate/type/select owner content.
assert 'TITLEHELPER_SAFE_ISOLATED_SEARCH_PRESS' in new
assert 'TITLEHELPER_SAFE_ISOLATED_SEARCH_PID' in new
assert 'self.recentRestorer.probeIsolatedSearchPress(' in new
assert 'isolated-search-press success=' in new
press_probe = restorer.split('    func probeIsolatedSearchPress(', 1)[1].split(
    '    // Explicit opt-in, read-only measurement', 1)[0]
assert 'app.processIdentifier == expectedPID' in press_probe
assert 'expected.count == 8' in press_probe
assert 'expected[expectedID] == false' in press_probe
assert 'expected.values.filter({ $0 }).count == 3' in press_probe
assert 'actual == expected' in press_probe
assert 'kAXFocusedWindowAttribute' in press_probe
assert 'String(CFHash(rawFocused as! AXUIElement)) == expectedID' in press_probe
assert 'scan.buttons.count == 1' in press_probe
assert 'scan.inputs == 0, scan.dialogs == 0' in press_probe
assert 'press(scan.buttons[0])' in press_probe
assert 'baselineSafe().0' in press_probe
assert 'searchUIScan(target)' in press_probe
assert 'fileNewWindow(' not in press_probe
assert 'app.activate()' not in press_probe
assert 'AXUIElementSetAttributeValue' not in press_probe
assert 'dockRecentMatches(' not in press_probe

# Reversible isolated Search contrast must not touch owner windows or results.
assert 'TITLEHELPER_SAFE_ISOLATED_QUERY_CONTRAST' in new
assert 'self.recentRestorer.probeIsolatedSearchContrast(' in new
assert 'isolated-query-contrast success=' in new
contrast_probe = restorer.split(
    '    func probeIsolatedSearchContrast(', 1
)[1].split('    // Read-only capability check', 1)[0]
for required in [
    'expected.count == 8', 'expected[expectedID] == false',
    'expected.values.filter({ $0 }).count == 3',
    'targetSafe()', 'kAXFocusedWindowAttribute',
    'AXUIElementIsAttributeSettable', 'AXUIElementSetAttributeValue',
    'zzqv_noresults_20261029_isolated8',
    '"ChatGPT" as NSString', 'noMatchReadback',
    'restored=', 'contrastObserved=', 'before=', 'noMatch=', 'after=',
    'originalsPreserved=', 'probeIsolatedSearchResultActions('
]:
    assert required in contrast_probe, required
for forbidden in [
    'AXUIElementPerformAction', 'fileNewWindow(', 'app.activate(',
    'dockRecentMatches(', 'sendMessage(', 'typeText(', 'press(',
    'NSLog(', 'print('
]:
    assert forbidden not in contrast_probe, forbidden
