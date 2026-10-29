import Foundation

// Research-stage planning only. Never navigates, changes windows, or persists URLs.
// Identity must come from an independently verified conversation-specific route.
// A saved window is an occurrence, not merely a distinct conversation: two native
// windows may intentionally display the same conversation or share a title.
enum ConversationRestorePlanner {
    struct SavedWindow {
        let title: String
        let routeURL: String?
    }

    struct CurrentWindow {
        let routeURL: String?
    }

    struct Target {
        let savedIndex: Int
        let title: String
        let identity: ConversationRouteIdentity
    }

    enum BlockReason: String {
        case unverifiedCurrentWindow
        case missingSavedIdentity
        case invalidSavedIdentity
        case targetLimitExceeded
    }

    struct Blocked {
        let savedIndex: Int
        let reason: BlockReason
    }

    struct Plan {
        let currentCensusVerified: Bool
        let targets: [Target]
        let alreadyPresentIndices: [Int]
        let blocked: [Blocked]
    }

    // Fail closed if ANY current native window lacks a verified conversation
    // identity: otherwise a missing title/URL could cause duplicate restoration.
    // For a verified census, subtract already-open multiplicity by conversation
    // UUID, not by title or ephemeral AX hash. Preserve saved window order.
    static func makePlan(saved: [SavedWindow], current: [CurrentWindow],
                         currentCensusComplete: Bool,
                         maxTargets: Int = 100) -> Plan {
        guard currentCensusComplete else {
            return Plan(
                currentCensusVerified: false, targets: [],
                alreadyPresentIndices: [],
                blocked: saved.indices.map {
                    Blocked(savedIndex: $0, reason: .unverifiedCurrentWindow)
                })
        }
        var openCounts: [UUID: Int] = [:]
        for window in current {
            guard let raw = window.routeURL,
                  let identity = ConversationRouteIdentity.parse(raw) else {
                return Plan(
                    currentCensusVerified: false, targets: [],
                    alreadyPresentIndices: [],
                    blocked: saved.indices.map {
                        Blocked(savedIndex: $0, reason: .unverifiedCurrentWindow)
                    })
            }
            openCounts[identity.conversationID, default: 0] += 1
        }

        var targets: [Target] = []
        var alreadyPresent: [Int] = []
        var blocked: [Blocked] = []
        let limit = max(0, maxTargets)
        for (index, window) in saved.enumerated() {
            guard let raw = window.routeURL, !raw.isEmpty else {
                blocked.append(Blocked(savedIndex: index, reason: .missingSavedIdentity))
                continue
            }
            guard let identity = ConversationRouteIdentity.parse(raw) else {
                blocked.append(Blocked(savedIndex: index, reason: .invalidSavedIdentity))
                continue
            }
            let key = identity.conversationID
            if openCounts[key, default: 0] > 0 {
                openCounts[key, default: 0] -= 1
                alreadyPresent.append(index)
                continue
            }
            guard targets.count < limit else {
                blocked.append(Blocked(savedIndex: index, reason: .targetLimitExceeded))
                continue
            }
            targets.append(Target(savedIndex: index, title: window.title,
                                  identity: identity))
        }
        return Plan(currentCensusVerified: true, targets: targets,
                    alreadyPresentIndices: alreadyPresent, blocked: blocked)
    }
}
