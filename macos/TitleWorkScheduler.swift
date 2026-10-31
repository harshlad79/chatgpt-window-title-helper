import Foundation

// Mirrors the proven Windows priority model without retaining AX elements.
// Mutated only on the AppKit main thread.
struct TitleWorkScheduler {
    enum Priority: Int {
        case background = 0
        case active = 1
        case immediate = 2
    }

    private struct Pending {
        var priority: Priority
        let order: UInt64
    }

    private var pending: [String: Pending] = [:]
    private var due: [String: Date] = [:]
    private var failures: [String: Int] = [:]
    private var counter: UInt64 = 0

    var hasPending: Bool { !pending.isEmpty }

    mutating func reconcile(_ identities: Set<String>) {
        for key in due.keys where !identities.contains(key) {
            due.removeValue(forKey: key)
            failures.removeValue(forKey: key)
            pending.removeValue(forKey: key)
        }
        for key in pending.keys where !identities.contains(key) {
            pending.removeValue(forKey: key)
        }
        for key in identities.sorted() where due[key] == nil {
            request(key, priority: .immediate)
        }
    }

    mutating func request(_ key: String, priority: Priority) {
        guard !key.isEmpty else { return }
        if var existing = pending[key] {
            if priority.rawValue > existing.priority.rawValue {
                existing.priority = priority
                pending[key] = existing
            }
        } else {
            counter &+= 1
            pending[key] = Pending(priority: priority, order: counter)
        }
    }

    mutating func requestOneOverdue(_ visible: Set<String>, now: Date) {
        guard let candidate = visible
            .filter({ due[$0].map { $0 <= now } ?? false && pending[$0] == nil })
            .min(by: {
                let left = due[$0] ?? .distantFuture
                let right = due[$1] ?? .distantFuture
                return left == right ? $0 < $1 : left < right
            })
        else { return }
        request(candidate, priority: .background)
    }

    mutating func pop() -> String? {
        guard let best = pending.max(by: {
            if $0.value.priority.rawValue != $1.value.priority.rawValue {
                return $0.value.priority.rawValue < $1.value.priority.rawValue
            }
            return $0.value.order > $1.value.order
        }) else { return nil }
        pending.removeValue(forKey: best.key)
        return best.key
    }

    mutating func complete(_ key: String, success: Bool, now: Date) {
        let failureCount = success ? 0 : min(5, (failures[key] ?? 0) + 1)
        failures[key] = failureCount
        let interval = success ? 20.0 : min(30.0, pow(2.0, Double(failureCount)))
        due[key] = now.addingTimeInterval(interval)
    }
}
