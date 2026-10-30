import Foundation

@main
struct ConversationRestorePlannerTests {
    static func main() {
        let a = "12345678-1234-1234-1234-123456789abc"
        let b = "87654321-4321-4321-4321-cba987654321"
        let c = "abcdefab-cdef-abcd-efab-cdefabcdefab"
        func route(_ id: String) -> String { "https://chatgpt.com/c/\(id)" }
        func saved(_ title: String, _ url: String?) -> ConversationRestorePlanner.SavedWindow {
            .init(title: title, routeURL: url)
        }
        func current(_ url: String?) -> ConversationRestorePlanner.CurrentWindow {
            .conversation(routeURL: url)
        }
        func check(_ ok: Bool, _ label: String) {
            precondition(ok, "planner failed: \(label)")
            passed += 1
        }
        func plan(saved: [ConversationRestorePlanner.SavedWindow],
                  current: [ConversationRestorePlanner.CurrentWindow],
                  currentCensusComplete: Bool,
                  observedNativeWindowCount: Int? = nil,
                  maxTargets: Int = 100) -> ConversationRestorePlanner.Plan {
            ConversationRestorePlanner.makePlan(
                saved: saved, current: current,
                currentCensusComplete: currentCensusComplete,
                observedNativeWindowCount: observedNativeWindowCount ?? current.count,
                maxTargets: maxTargets)
        }
        var passed = 0

        // Same title, different conversation IDs: two independent windows.
        let distinct = plan(
            saved: [saved("same", route(a)), saved("same", route(b))], current: [], currentCensusComplete: true)
        check(distinct.currentCensusVerified, "empty current census valid")
        check(distinct.targets.count == 2, "distinct IDs with same title")
        check(distinct.targets.map(\.savedIndex) == [0, 1], "stable order")

        // Same conversation in two windows: subtract only ONE existing window.
        let repeated = plan(
            saved: [saved("first", route(a)), saved("second", route(a))],
            current: [current(route(a))], currentCensusComplete: true)
        check(repeated.targets.count == 1, "preserve window multiplicity")
        check(repeated.targets.first?.savedIndex == 1, "second occurrence missing")
        check(repeated.alreadyPresentIndices == [0], "consume one occurrence")
        let noneOpen = plan(
            saved: [saved("first", route(a)), saved("second", route(a))], current: [], currentCensusComplete: true)
        check(noneOpen.targets.count == 2, "two windows same ID both absent")
        let bothOpen = plan(
            saved: [saved("first", route(a)), saved("second", route(a))],
            current: [current(route(a)), current(route(a))], currentCensusComplete: true)
        check(bothOpen.targets.isEmpty, "both occurrences present")
        check(bothOpen.alreadyPresentIndices == [0, 1], "both indices consumed")

        // Same UUID with a project route is still one conversation identity.
        let project = "https://chatgpt.com/g/g-p-test/c/\(a)"
        let projectMatch = plan(
            saved: [saved("project", project)], current: [current(route(a))], currentCensusComplete: true)
        check(projectMatch.targets.isEmpty, "project alias same conversation")
        check(projectMatch.alreadyPresentIndices == [0], "project alias consumed")

        // Missing/invalid saved identity is reported, never guessed from title.
        let partial = plan(
            saved: [saved("missing", nil), saved("bad", "http://chatgpt.com/c/\(a)"),
                    saved("valid", route(b))], current: [], currentCensusComplete: true)
        check(partial.targets.count == 1, "valid target remains")
        check(partial.targets.first?.savedIndex == 2, "valid index retained")
        check(partial.blocked.map(\.reason) ==
              [.missingSavedIdentity, .invalidSavedIdentity], "block reasons")

        // One unidentified currently open native window blocks ALL restoration.
        let unknown = plan(
            saved: [saved("A", route(a)), saved("B", route(b))],
            current: [current(route(c)), current(nil)], currentCensusComplete: true)
        check(!unknown.currentCensusVerified, "missing current ID unsafe")
        check(unknown.targets.isEmpty, "no actions on unsafe census")
        check(unknown.blocked.count == 2, "all saved blocked on unsafe census")
        check(unknown.blocked.allSatisfy { $0.reason == .unverifiedCurrentWindow },
              "unsafe census reason")
        let invalidCurrent = plan(
            saved: [saved("A", route(a))], current: [current("not a URL")], currentCensusComplete: true)
        check(!invalidCurrent.currentCensusVerified, "invalid current ID unsafe")

        // Explicit target cap, never silently drop remaining window occurrences.
        let limited = plan(
            saved: [saved("A", route(a)), saved("B", route(b)),
                    saved("C", route(c))], current: [], currentCensusComplete: true, maxTargets: 2)
        check(limited.targets.count == 2, "limit enforced")
        check(limited.blocked.count == 1, "limit overflow reported")
        check(limited.blocked.first?.reason == .targetLimitExceeded, "limit reason")
        let zero = plan(
            saved: [saved("A", route(a))], current: [], currentCensusComplete: true, maxTargets: -1)
        check(zero.targets.isEmpty && zero.blocked.count == 1, "negative limit safe")

        // An empty AX scan is NOT proof that the native window census is complete.
        let incomplete = plan(
            saved: [saved("A", route(a))], current: [],
            currentCensusComplete: false)
        check(!incomplete.currentCensusVerified, "incomplete empty census unsafe")
        check(incomplete.targets.isEmpty, "incomplete census no restore")
        check(incomplete.blocked.count == 1, "incomplete census reported")

        // Independently verified non-conversation native windows may be skipped
        // from UUID counting, but never omitted from the raw AX census.
        let verifiedGeneric = plan(
            saved: [saved("A", route(a)), saved("B", route(b))],
            current: [current(route(a)), .verifiedNonConversation,
                      .verifiedNonConversation], currentCensusComplete: true)
        check(verifiedGeneric.currentCensusVerified, "verified nonchat census")
        check(verifiedGeneric.alreadyPresentIndices == [0], "existing chat counted")
        check(verifiedGeneric.targets.map(\.savedIndex) == [1], "missing chat planned")

        let unknownGeneric = plan(
            saved: [saved("B", route(b))],
            current: [current(route(a)), .unknown], currentCensusComplete: true)
        check(!unknownGeneric.currentCensusVerified, "unknown generic blocks")
        check(unknownGeneric.targets.isEmpty, "unknown generic no action")
        check(unknownGeneric.blocked.first?.reason == .unverifiedCurrentWindow,
              "unknown generic reason")

        let omittedNative = plan(
            saved: [saved("B", route(b))],
            current: [current(route(a))], currentCensusComplete: true,
            observedNativeWindowCount: 8)
        check(!omittedNative.currentCensusVerified, "AX count mismatch blocks")
        check(omittedNative.targets.isEmpty, "AX count mismatch no action")
        let negativeCount = plan(
            saved: [saved("B", route(b))],
            current: [], currentCensusComplete: true,
            observedNativeWindowCount: -1)
        check(!negativeCount.currentCensusVerified, "negative raw count blocks")

        print("ConversationRestorePlanner: \(passed) assertions PASS")
    }
}
