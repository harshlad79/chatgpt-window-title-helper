import Foundation

// Crash-tolerant local snapshots; never uses transient AX hashes as durable
// identities. Exact-title matching remains explicitly best-effort.
final class WindowSessionHistoryStore {
    struct Snapshot: Codable {
        var version: Int = 1
        var appPID: Int32 = 0
        var lastCompleteOpen: [String] = []
        // Optional for compatibility with schema-1 manifests written before this guard.
        var lastCompleteObservedAt: Date? = nil
        var previousSessionOpen: [String] = []
        var recentTitles: [String] = []
    }

    // Separate evidence only. Never use this partial snapshot as a Restore All
    // target or as a durable conversation/window identity.
    struct PartialEntry: Codable, Equatable {
        let windowIndex: Int
        let title: String
        let minimized: Bool?
    }

    struct PartialSnapshot: Codable {
        var version: Int = 1
        let appPID: Int32
        let observedAt: Date
        let windowCount: Int
        let entries: [PartialEntry]
    }

    private let file: URL
    private let partialFile: URL
    private let legacyManifestModifiedAt: Date?
    private(set) var partialSnapshot: PartialSnapshot?
    private(set) var snapshot: Snapshot
    // ChatGPT normally closes windows one by one on Quit. Hold shrink
    // candidates until the app has remained alive with a stable smaller set.
    // If it quits during the grace period, the last full set is preserved.
    private var pendingShrink: (pid: Int32, titles: [String], since: Date)?
    private let settleInterval: TimeInterval = 12

    init(file: URL? = nil) {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ChatGPTTitleOverlay")
        self.file = file ?? support.appendingPathComponent("window-session-history.json")
        self.partialFile = self.file.deletingLastPathComponent()
            .appendingPathComponent("window-session-partial.json")
        self.legacyManifestModifiedAt = (try? FileManager.default.attributesOfItem(
            atPath: self.file.path)[.modificationDate]) as? Date
        if let data = try? Data(contentsOf: self.file),
           let loaded = try? JSONDecoder().decode(Snapshot.self, from: data),
           loaded.version == 1 {
            self.snapshot = loaded
            // Migrate files written by the earlier 0644 implementation
            // even when the JSON data itself has not changed.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: self.file.path)
        } else {
            self.snapshot = Snapshot()
        }
        if let bytes = try? Data(contentsOf: partialFile),
           let loaded = try? JSONDecoder().decode(PartialSnapshot.self, from: bytes),
           loaded.version == 1 {
            self.partialSnapshot = loaded
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: partialFile.path)
        }
    }

    // A minimized AXWindow can retain its native caption after its AXWebArea
    // becomes inaccessible. Keep that caption as PARTIAL evidence only:
    // never promote it to a complete restore manifest or a conversation ID.
    static func partialEvidenceTitle(cached: String?, native: String,
                                     minimized: Bool) -> String? {
        func valid(_ value: String?) -> String? {
            guard let title = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, title != "ChatGPT", title.count <= 512 else {
                return nil
            }
            return title
        }
        if let title = valid(cached) { return title }
        return minimized ? valid(native) : nil
    }

    private func uniqueTitles(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        return titles.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                $0.count <= 512 && seen.insert($0).inserted
        }
    }

    // Only persist a complete title census. A partially refreshed AX cache,
    // missing accessibility access or a temporary zero-window result MUST
    // NOT erase the previous-session snapshot.
    @discardableResult
    func observe(pid: pid_t, titles: [String], windowCount: Int,
                 now: Date = Date()) -> Bool {
        // Titles are not conversation identities. A duplicate title is an
        // ambiguous native-window census, never a complete restore manifest.
        // Preserve the last known complete set until stable route IDs exist.
        guard pid > 0, windowCount > 0, titles.count == windowCount,
              Set(titles).count == windowCount,
              titles.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    $0.count <= 512
              }) else { return false }

        let current = uniqueTitles(titles)
        // Never accidentally replace previously saved multiple windows by
        // the subset exposed during sequential normal shutdown.
        let sameProcess = snapshot.appPID == Int32(pid)
        if sameProcess && current.count < snapshot.lastCompleteOpen.count {
            if let pending = pendingShrink,
               pending.pid == Int32(pid), pending.titles == current,
               now.timeIntervalSince(pending.since) >= settleInterval {
                pendingShrink = nil
            } else {
                if pendingShrink?.pid != Int32(pid) ||
                   pendingShrink?.titles != current {
                    pendingShrink = (Int32(pid), current, now)
                }
                return true
            }
        } else {
            pendingShrink = nil
        }
        var next = snapshot
        if next.appPID != Int32(pid) {
            if hasInterveningPartialSession(pid: pid) {
                // A later PID had an incomplete census. The old complete set
                // is NOT the immediately preceding session: never promote it.
                next.previousSessionOpen = []
            } else if !next.lastCompleteOpen.isEmpty {
                next.previousSessionOpen = next.lastCompleteOpen
            }
            next.appPID = Int32(pid)
        }
        if next.appPID != snapshot.appPID || next.lastCompleteOpen != current {
            next.lastCompleteObservedAt = now
        }
        next.lastCompleteOpen = current
        for title in current.reversed() {
            next.recentTitles.removeAll { $0 == title }
            next.recentTitles.insert(title, at: 0)
        }
        next.recentTitles = Array(next.recentTitles.prefix(250))
        guard next.appPID != snapshot.appPID ||
              next.lastCompleteOpen != snapshot.lastCompleteOpen ||
              next.previousSessionOpen != snapshot.previousSessionOpen ||
              next.recentTitles != snapshot.recentTitles else { return true }
        let old = snapshot
        snapshot = next
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(next)
            try bytes.write(to: file, options: [.atomic])
            // Conversation titles belong to the local account, not other
            // macOS users sharing this computer.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            snapshot = old
            TitleHelperDiagnostics.shared.record(
                "history-save-failed code=\((error as NSError).code)")
            return false
        }
    }

    // Best-observed per-window evidence, independent of the complete manifest.
    // AX ordering is ephemeral: windowIndex is evidence of a single census,
    // NEVER a persistent identifier or a reason to open a conversation.
    // Missing/unknown windows remain explicit via windowCount - entries.count.
    @discardableResult
    func observePartial(pid: pid_t, windowCount: Int,
                        entries: [PartialEntry], now: Date = Date()) -> Bool {
        guard pid > 0, windowCount > 0, entries.count <= windowCount,
              Set(entries.map { $0.windowIndex }).count == entries.count,
              entries.allSatisfy({
                  $0.windowIndex >= 0 && $0.windowIndex < windowCount &&
                  !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.count <= 512
              }) else { return false }
        // Never replace stronger evidence with a temporary AX-cache drop,
        // a zero-title restart or a transient sequential Quit shrink.
        guard !entries.isEmpty else { return false }
        let ordered = entries.sorted { $0.windowIndex < $1.windowIndex }
        if let old = partialSnapshot {
            if old.appPID == Int32(pid) {
                if ordered.count < old.entries.count ||
                   windowCount < old.windowCount { return false }
                if old.windowCount == windowCount && old.entries == ordered {
                    return true
                }
            }
        }
        let next = PartialSnapshot(appPID: Int32(pid), observedAt: now,
                                   windowCount: windowCount, entries: ordered)
        do {
            try FileManager.default.createDirectory(
                at: partialFile.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(next)
            try bytes.write(to: partialFile, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: partialFile.path)
            partialSnapshot = next
            return true
        } catch {
            TitleHelperDiagnostics.shared.record(
                "history-partial-save-failed code=\((error as NSError).code)")
            return false
        }
    }

    // An incomplete census from a distinct intervening ChatGPT PID proves
    // the saved complete titles predate the immediately preceding session.
    // The partial file is evidence of a process, NOT a restore target.
    // Older schema-1 manifests have no observedAt; use their file mtime.
    func hasInterveningPartialSession(pid: pid_t) -> Bool {
        // Once the current PID has a complete census, the transition was
        // already reconciled by observe(); never invalidate its prior manifest.
        guard pid > 0, snapshot.appPID != Int32(pid),
              let partial = partialSnapshot, partial.appPID > 0,
              partial.appPID != snapshot.appPID,
              partial.appPID != Int32(pid) else { return false }
        let completeAt = snapshot.lastCompleteObservedAt ??
            legacyManifestModifiedAt ?? .distantPast
        return partial.observedAt > completeAt
    }

    // If the ChatGPT process restarted while AX still lacks a complete
    // title census, the saved previous process's window list is recoverable.
    // Never treat unavailable AX data as a reason to hide that durable list.
    func hasPendingRestart(pid: pid_t) -> Bool {
        pid > 0 && snapshot.appPID > 0 && snapshot.appPID != Int32(pid) &&
            !lastSessionTargets(pid: pid).isEmpty
    }

    // Until the next process has a complete AX census, lastCompleteOpen
    // belongs to the immediately preceding process; previousSessionOpen
    // is older. For the same PID, recover the prior process's manifest.
    func lastSessionTargets(pid: pid_t) -> [String] {
        // Fail closed: PID A complete -> PID B partial -> PID C current.
        // A's title list cannot be called B's last session.
        if hasInterveningPartialSession(pid: pid) { return [] }
        if pid > 0 && snapshot.appPID > 0 && snapshot.appPID != Int32(pid) {
            return snapshot.lastCompleteOpen
        }
        return snapshot.previousSessionOpen.isEmpty
            ? snapshot.lastCompleteOpen : snapshot.previousSessionOpen
    }

    func recoverable(excluding open: [String], pid: pid_t,
                     limit: Int = 8) -> [String] {
        let existing = Set(open)
        let combined = lastSessionTargets(pid: pid)
        var seen = Set<String>()
        return Array(combined.filter {
            !existing.contains($0) && seen.insert($0).inserted
        }.prefix(max(0, limit)))
    }
}
