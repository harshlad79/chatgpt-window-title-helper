import Foundation

private var passes = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("FAIL: \(name)") }
    passes += 1
}
typealias E = FocusedMenuURLProbe.LinkEvidence
let id = "123e4567-e89b-12d3-a456-426614174000"
let direct = "https://chatgpt.com/c/\(id)"
let project = "https://chatgpt.com/g/g-test/c/\(id)"
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: direct) == .conversationURL, "direct URL")
check(FocusedMenuURLProbe.classify(label: "chatgpt.com에서 열기",
                                   url: project) == .conversationURL, "project URL")
check(FocusedMenuURLProbe.classify(label: " OPEN ON CHATGPT.COM ",
                                   url: direct) == .conversationURL, "normalized label")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: nil) == .missingURL, "nil URL")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: "") == .missingURL, "empty URL")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: "https://example.com/c/\(id)") == .invalidURL,
      "external host")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: "https://chatgpt.com/c/not-an-id") == .invalidURL,
      "invalid ID")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: "https://chatgpt.com/c/\(id)?token=x") == .invalidURL,
      "query rejected")
check(FocusedMenuURLProbe.classify(label: "Share",
                                   url: direct) == .unrelated, "not a navigation item")
check(FocusedMenuURLProbe.classify(label: "Delete",
                                   url: direct) == .unrelated, "no destructive item")
check(FocusedMenuURLProbe.classify(label: "Open on chatgpt.com",
                                   url: "javascript:alert(1)") == .invalidURL,
      "script URL rejected")
check(FocusedMenuURLProbe.classify(label: "chatgpt.com에서 열기…",
                                   url: direct) == .conversationURL, "localized ellipsis")
// A valid route with an unknown localized label is counted as a diagnostic
// candidate only; it never becomes a verified current-window identity.
check(FocusedMenuURLProbe.isConversationRouteCandidate(direct),
      "route candidate independent of menu label")
check(FocusedMenuURLProbe.isConversationRouteCandidate(project),
      "project route candidate")
check(!FocusedMenuURLProbe.isConversationRouteCandidate(nil),
      "nil candidate rejected")
check(!FocusedMenuURLProbe.isConversationRouteCandidate("https://evil.example/c/\(id)"),
      "foreign candidate rejected")
check(!FocusedMenuURLProbe.isConversationRouteCandidate("https://chatgpt.com/c/\(id)?token=x"),
      "query candidate rejected")
// The fast sampler is opt-in, foreground-only and serialized.
check(!FocusedMenuProbeCadence.shouldSample(trusted: false, frontmostPID: 12,
    targetPID: 12, inFlight: false, elapsed: 1), "AX trust required")
check(!FocusedMenuProbeCadence.shouldSample(trusted: true, frontmostPID: 13,
    targetPID: 12, inFlight: false, elapsed: 1), "foreground PID required")
check(!FocusedMenuProbeCadence.shouldSample(trusted: true, frontmostPID: 12,
    targetPID: 0, inFlight: false, elapsed: 1), "valid PID required")
check(!FocusedMenuProbeCadence.shouldSample(trusted: true, frontmostPID: 12,
    targetPID: 12, inFlight: true, elapsed: 1), "single flight")
check(!FocusedMenuProbeCadence.shouldSample(trusted: true, frontmostPID: 12,
    targetPID: 12, inFlight: false, elapsed: 0.1), "minimum spacing")
check(FocusedMenuProbeCadence.shouldSample(trusted: true, frontmostPID: 12,
    targetPID: 12, inFlight: false, elapsed: 0.31), "foreground sample allowed")
check(FocusedMenuProbeCadence.timerInterval < 2.0, "faster than refresh")
check(!FocusedMenuProbeCadence.shouldReport(elapsed: 59, interval:
    FocusedMenuProbeCadence.heartbeatInterval), "heartbeat throttled")
check(FocusedMenuProbeCadence.shouldReport(elapsed: 60, interval:
    FocusedMenuProbeCadence.heartbeatInterval), "heartbeat due")
check(!FocusedMenuProbeCadence.shouldReport(elapsed: 29, interval:
    FocusedMenuProbeCadence.noMenuReportInterval), "no-menu report throttled")
check(FocusedMenuProbeCadence.shouldReport(elapsed: 30, interval:
    FocusedMenuProbeCadence.noMenuReportInterval), "no-menu report due")
check(!FocusedMenuProbeCadence.shouldReport(elapsed: 99, interval: 0),
    "invalid telemetry interval disabled")
// Fail-closed identity parsing: candidate URLs must not become restore IDs
// unless they are exact private conversation routes. All IDs below are
// synthetic; no owner conversation URL or clipboard is inspected.
let parsedDirect = ConversationRouteIdentity.parse(direct)
let parsedProject = ConversationRouteIdentity.parse(project)
check(parsedDirect?.conversationID.uuidString.lowercased() == id,
      "exact direct conversation UUID")
check(parsedDirect?.gptSlug == nil, "direct route has no project")
check(parsedDirect?.canonicalURL.absoluteString == direct,
      "direct route canonical round trip")
check(parsedProject?.gptSlug == "g-test",
      "project slug preserved")
check(parsedProject?.canonicalURL.absoluteString == project,
      "project route canonical round trip")
check(ConversationRouteIdentity.parse("https://www.chatgpt.com/c/\(id)")?
      .canonicalURL.absoluteString == direct,
      "approved www host normalizes to canonical host")
check(ConversationRouteIdentity.parse("http://chatgpt.com/c/\(id)") == nil,
      "plaintext HTTP rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com.evil.test/c/\(id)") == nil,
      "host suffix spoof rejected")
check(ConversationRouteIdentity.parse("https://user@chatgpt.com/c/\(id)") == nil,
      "userinfo rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com:443/c/\(id)") == nil,
      "explicit port rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/c/\(id)#frag") == nil,
      "fragment rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/c/\(id)/") == nil,
      "trailing slash rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/g/%2e%2e/c/\(id)") == nil,
      "encoded project path rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/g/../../c/\(id)") == nil,
      "path traversal rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/g/bad.slug/c/\(id)") == nil,
      "unapproved project slug rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/c/\(id)?model=auto") == nil,
      "query parameters rejected")
check(ConversationRouteIdentity.parse("https://chatgpt.com/c/not-a-uuid") == nil,
      "non-UUID route rejected")
print("PASS focused menu URL policy \(passes) assertions")
print("LIVE_AX_MENU_URL=NOT_TESTED")
