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

    // Generic titles do not establish a non-conversation window.
    // Classification requires independent positive AX evidence.
    enum CurrentWindow {
        case conversation(routeURL: String?)
        case verifiedNonConversation
        case unknown
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

    // Fail closed on unknown windows or unverified conversation identities.
    // Include verified non-conversation windows in the complete native AX count
    // but exclude them from conversation UUID counts. Never infer from title.
    static func makePlan(saved: [SavedWindow], current: [CurrentWindow],
                         currentCensusComplete: Bool,
                         observedNativeWindowCount: Int,
                         maxTargets: Int = 100) -> Plan {
        func unsafePlan() -> Plan {
            Plan(currentCensusVerified: false, targets: [],
                 alreadyPresentIndices: [],
                 blocked: saved.indices.map {
                     Blocked(savedIndex: $0, reason: .unverifiedCurrentWindow)
                 })
        }
        // An AX scan reporting 8 windows cannot pass just 3 recognized ones.
        // Include minimized, generic, and unclassified windows in this count.
        guard currentCensusComplete, observedNativeWindowCount >= 0,
              current.count == observedNativeWindowCount else {
            return unsafePlan()
        }
        var openCounts: [UUID: Int] = [:]
        for window in current {
            switch window {
            case .verifiedNonConversation:
                continue
            case .unknown:
                return unsafePlan()
            case .conversation(let routeURL):
                guard let raw = routeURL,
                      let identity = ConversationRouteIdentity.parse(raw) else {
                    return unsafePlan()
                }
                openCounts[identity.conversationID, default: 0] += 1
            }
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
