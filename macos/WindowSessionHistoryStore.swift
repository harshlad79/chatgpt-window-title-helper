import Foundation

// Crash-tolerant local snapshots; never uses transient AX hashes as durable
// identities. Exact-title matching remains explicitly best-effort.
final class WindowSessionHistoryStore {
    struct Snapshot: Codable {
        var version: Int = 1
        var appPID: Int32 = 0
        var lastCompleteOpen: [String] = []
        var previousSessionOpen: [String] = []
        var recentTitles: [String] = []
    }

    private let file: URL
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
        guard pid > 0, windowCount > 0, titles.count == windowCount,
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
            if !next.lastCompleteOpen.isEmpty {
                next.previousSessionOpen = next.lastCompleteOpen
            }
            next.appPID = Int32(pid)
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
