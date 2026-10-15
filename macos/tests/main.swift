import Foundation

private var passes = 0
func expect(_ condition: @autoclosure () -> Bool, _ text: String) {
    guard condition() else { fatalError("FAILED: \(text)") }
    passes += 1
}
let now = Date(timeIntervalSince1970: 1000)

// New windows are requested immediately, no redundant work on stable windows.
var q = TitleWorkScheduler()
q.reconcile(["a", "b"])
expect(q.hasPending, "initial windows scheduled")
q.request("a", priority: .active)
q.request("b", priority: .immediate)
q.request("a", priority: .immediate)
expect(q.pop() == "a", "stable FIFO for immediate priority")
expect(q.pop() == "b", "other immediate new window")
expect(q.pop() == nil, "duplicate requests coalesced")

q.complete("a", success: true, now: now)
q.complete("b", success: true, now: now)
q.reconcile(["a", "b"])
expect(q.pop() == nil, "successful titles not polled on discovery")
q.requestOneOverdue(["a", "b"], now: now.addingTimeInterval(19))
expect(q.pop() == nil, "no work before 20s due")

// Exactly one old window per tick; urgent event wins over due background.
q.requestOneOverdue(["a", "b"], now: now.addingTimeInterval(21))
q.request("b", priority: .immediate)
expect(q.pop() == "b", "title notification wins over overdue tick")
expect(q.pop() == "a", "one overdue window queued")
expect(q.pop() == nil, "only one stale window per tick")

// Failure backoff: a missing tree cannot trigger a hot loop.
q.complete("a", success: false, now: now.addingTimeInterval(21))
q.complete("b", success: true, now: now.addingTimeInterval(21))
q.requestOneOverdue(["a", "b"], now: now.addingTimeInterval(22))
expect(q.pop() == nil, "failure waits >= 2 seconds")
q.requestOneOverdue(["a", "b"], now: now.addingTimeInterval(24))
expect(q.pop() == "a", "failed title eventually retried")

// Lost windows cannot remain in the pending queue.
q.request("a", priority: .immediate)
q.reconcile(["b", "c"])
expect(q.pop() == "c", "closed window removed; new window gets immediate work")
expect(q.pop() == nil, "no stale window pending")

// Only one-character titles and empty title logic are handled at call sites:
// the queue has no minimum length or title predicate.
q.request("c", priority: .immediate)
expect(q.pop() == "c", "window identity never filtered by title length")
print("PASS TitleWorkScheduler \(passes) assertions")


// Actual one-character titles are accepted by the fingerprint diagnostic.
// Fingerprints reveal length, not the original content.
let shortKorean = TitleHelperDiagnostics.fingerprint("가")
let shortEnglish = TitleHelperDiagnostics.fingerprint("A")
expect(shortKorean.hasPrefix("len1:sha"), "Korean one-character title")
expect(shortEnglish.hasPrefix("len1:sha"), "English one-character title")
expect(shortKorean != shortEnglish, "distinct fingerprints")
expect(TitleHelperDiagnostics.fingerprint("ChatGPT").hasPrefix("len7:sha"),
       "generic title retains length")

// Title changes can arrive before Chromium commits its AXWebArea.Title.
var retries = TitleRevisionRetryPlan()
expect(retries.begin("winA", hasCachedTitle: false) == nil,
       "no retries without an original title to compare")
let first = retries.begin("winA", hasCachedTitle: true)!
expect(retries.isActive("winA", generation: first), "first ticket active")
let second = retries.begin("winA", hasCachedTitle: true)!
expect(!retries.isActive("winA", generation: first),
       "superseded AX event cannot schedule stale reads")
expect(retries.isActive("winA", generation: second), "latest ticket remains active")
retries.complete("winA")
expect(!retries.isActive("winA", generation: second),
       "title update cancels pending follow-up reads")
let third = retries.begin("winB", hasCachedTitle: true)!
retries.retainOnly(["winA"])
expect(!retries.isActive("winB", generation: third),
       "closed window discards pending retries")
expect(TitleRevisionRetryPlan.delays.count == 6,
       "bounded retry plan must not run indefinitely")
expect(TitleRevisionRetryPlan.delays.last! <= 6.0,
       "last retry must happen within 6 seconds")
print("PASS TitleWorkScheduler + AX title retries \(passes) assertions")
