import Foundation

// Per-window bounded retries for the asynchronous Chromium AXWebArea title.
// Notifications may arrive before the updated AXTitle becomes available.
// Main-thread only, never carries a conversation title or AX element.
struct TitleRevisionRetryPlan {
    static let delays: [TimeInterval] = [0.25, 0.6, 1.2, 2.2, 4.0, 6.0]

    private var generations: [String: UInt64] = [:]
    private var sequence: UInt64 = 0

    mutating func begin(_ windowID: String, hasCachedTitle: Bool) -> UInt64? {
        guard hasCachedTitle, !windowID.isEmpty else { return nil }
        sequence &+= 1
        generations[windowID] = sequence
        return sequence
    }

    func isActive(_ windowID: String, generation: UInt64) -> Bool {
        generations[windowID] == generation
    }

    mutating func complete(_ windowID: String) {
        generations.removeValue(forKey: windowID)
    }

    mutating func retainOnly(_ windowIDs: Set<String>) {
        generations = generations.filter { windowIDs.contains($0.key) }
    }
}
