#!/usr/bin/env python3
"""Prove event-driven source retains the original NativeTitleSync verbatim."""
from pathlib import Path
import re

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
assert 'requestOneOverdue(visibleIDs, now: Date())' in new
assert 'titleScheduler.pop()' in new
assert 'NativeTitleSync()' in new
assert 'nativeSync.sync(pid: pid, windows: windows)' in new
assert old.count('SIGUSR1') == new.count('SIGUSR1')
print("PASS unchanged NativeTitleSync and event-driven wiring")
