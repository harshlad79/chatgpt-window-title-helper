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
assert 'sessionHistory.lastSessionTargets()' in new

assert 'Its own AXMenu is sufficient evidence' in Path('macos/DockMenuSidecar.swift').read_text()

assert 'lastAXWindowCensusSucceeded' in new
assert 'dockSidecar.updateHistory([])' in new
assert 'let complete = lastAXWindowCensusSucceeded &&' in new
