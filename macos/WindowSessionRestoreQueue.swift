import Foundation

// Deterministic, sequential, user-triggered restore queue.
// A cancel request stops *after* the in-flight native window action.
final class WindowSessionRestoreQueue {
    struct Progress {
        let finished: Int
        let total: Int
        let failed: Int
        let activeTitle: String?
        let running: Bool
        let cancelled: Bool
    }
    private var planned: [String] = []
    private var finished = 0
    private var failed = 0
    private var running = false
    private var cancelRequested = false
    private var generation = 0
    private var restoreAction: ((String, @escaping (Bool, String) -> Void) -> Void)?
    var onProgress: ((Progress) -> Void)?
    var onComplete: ((Progress) -> Void)?
    var onResult: ((String, Bool, String) -> Void)?

    var isRunning: Bool { running }

    @discardableResult
    func start(titles: [String], alreadyOpen: [String],
               action: @escaping (String, @escaping (Bool, String) -> Void) -> Void) -> Bool {
        guard !running else { return false }
        let open = Set(alreadyOpen)
        var seen = Set<String>()
        planned = Array(titles.filter {
            !open.contains($0) && !$0.isEmpty && seen.insert($0).inserted
        }.prefix(100))
        guard !planned.isEmpty else { return false }
        finished = 0
        failed = 0
        running = true
        cancelRequested = false
        generation &+= 1
        restoreAction = action
        advance(generation)
        return true
    }

    func cancel() {
        guard running else { return }
        cancelRequested = true
        publish(activeTitle: nil)
    }

    private func state(activeTitle: String?) -> Progress {
        Progress(finished: finished, total: planned.count,
                 failed: failed, activeTitle: activeTitle,
                 running: running, cancelled: cancelRequested)
    }

    private func publish(activeTitle: String?) {
        onProgress?(state(activeTitle: activeTitle))
    }

    private func advance(_ token: Int) {
        guard token == generation, running else { return }
        if cancelRequested || finished >= planned.count {
            running = false
            restoreAction = nil
            let end = state(activeTitle: nil)
            onProgress?(end)
            onComplete?(end)
            return
        }
        let title = planned[finished]
        publish(activeTitle: title)
        restoreAction?(title) { [weak self] success, reason in
            guard let self, self.running, token == self.generation else { return }
            self.onResult?(title, success, reason)
            self.finished += 1
            if !success { self.failed += 1 }
            // Always yield: no back-to-back UI menu actions in a single callback.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.advance(token)
            }
        }
    }
}


// The ChatGPT renderer updates the native AXWindow caption asynchronously.
// A one-shot check at 1.4 seconds incorrectly classified restored conversations
// as failures even though their titles appeared 5-10 seconds later.
enum WindowRestoreVerificationDecision: Equatable {
    case pending
    case success
    case failure
}

struct WindowRestoreVerificationPolicy {
    static let timeoutSeconds: TimeInterval = 16.0
    static let pollSeconds: TimeInterval = 0.7

    static func decide(elapsed: TimeInterval, expectedCount: Int,
                       actualCount: Int, newWindowTitleMatched: Bool,
                       originalsRetained: Bool) -> WindowRestoreVerificationDecision {
        if actualCount == expectedCount && newWindowTitleMatched && originalsRetained {
            return .success
        }
        return elapsed >= timeoutSeconds ? .failure : .pending
    }
}
