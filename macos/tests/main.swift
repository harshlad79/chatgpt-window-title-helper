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

// Disk persistence, crash/restart reconciliation, and incomplete AX scans.
let testDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("title-helper-history-\(UUID().uuidString)")
try! FileManager.default.createDirectory(
    at: testDirectory, withIntermediateDirectories: true)
let file = testDirectory.appendingPathComponent("state.json")
let history = WindowSessionHistoryStore(file: file)
expect(history.snapshot.appPID == 0, "empty state starts without PID")
expect(!history.observe(pid: 100, titles: [], windowCount: 0),
       "zero window transient cannot erase prior session")
expect(history.observe(pid: 100,
                       titles: ["대화 A", "대화 B"], windowCount: 2),
       "complete title census saved atomically")
expect(history.snapshot.lastCompleteOpen == ["대화 A", "대화 B"],
       "most recent complete window order is durable")
expect(!history.observe(pid: 100, titles: ["대화 A"], windowCount: 2),
       "incomplete AX cache cannot overwrite a two-window manifest")
expect(history.snapshot.lastCompleteOpen.count == 2,
       "incomplete refresh leaves saved complete state untouched")
let restartedHelper = WindowSessionHistoryStore(file: file)
expect(restartedHelper.snapshot.lastCompleteOpen.count == 2,
       "separate helper restart reloads full state")
expect(restartedHelper.observe(pid: 200, titles: ["대화 C"], windowCount: 1),
       "ChatGPT PID change starts new session")
expect(restartedHelper.snapshot.previousSessionOpen == ["대화 A", "대화 B"],
       "prior ChatGPT window set survives a process crash")
expect(restartedHelper.recoverable(excluding: ["대화 C"], pid: 200) ==
       ["대화 A", "대화 B"], "previous session appears first")
expect(restartedHelper.recoverable(excluding: ["대화 A", "대화 C"], pid: 200) ==
       ["대화 B"], "already reopened entries disappear from recovery")
expect(restartedHelper.observe(pid: 200, titles: ["대화 C", "대화 A"],
                               windowCount: 2),
       "reopened second window joins new session")
expect(restartedHelper.snapshot.previousSessionOpen.count == 2,
       "last session manifest not destroyed by restoring a window")
let finalReload = WindowSessionHistoryStore(file: file)
expect(finalReload.snapshot.appPID == 200, "atomic JSON reload current PID")
expect(!finalReload.observe(pid: 200, titles: [""], windowCount: 1),
       "untitled window cannot overwrite a valid manifest")
// Partial evidence is a separate 0600 file, never a Restore All target.
let partialEntries = [
    WindowSessionHistoryStore.PartialEntry(
        windowIndex: 0, title: "확인 A", minimized: false),
    WindowSessionHistoryStore.PartialEntry(
        windowIndex: 2, title: "확인 B", minimized: true)
]
expect(history.observePartial(pid: 100, windowCount: 4,
                              entries: partialEntries),
       "partial known titles persist even with unidentified windows")
expect(history.partialSnapshot?.entries.count == 2 &&
       history.partialSnapshot?.windowCount == 4,
       "partial snapshot explicitly records incomplete coverage")
expect(history.snapshot.lastCompleteOpen == ["대화 A", "대화 B"],
       "partial evidence never overwrites complete restore manifest")
expect(!history.observePartial(pid: 100, windowCount: 4, entries: []),
       "temporary zero-title AX result cannot erase partial evidence")
expect(!history.observePartial(pid: 100, windowCount: 4,
       entries: Array(partialEntries.prefix(1))),
       "AX title-cache drop cannot downgrade partial evidence")
expect(!history.observePartial(pid: 100, windowCount: 4,
       entries: [WindowSessionHistoryStore.PartialEntry(
           windowIndex: 4, title: "invalid", minimized: nil)]),
       "out-of-range window index rejected")
let partialReload = WindowSessionHistoryStore(file: file)
expect(partialReload.partialSnapshot?.entries == partialEntries,
       "separate helper restart reloads partial title and minimized evidence")
let partialPath = testDirectory.appendingPathComponent("window-session-partial.json")
let partialMode = (try! FileManager.default.attributesOfItem(
    atPath: partialPath.path)[.posixPermissions] as! NSNumber).intValue
expect(partialMode & 0o777 == 0o600,
       "partial conversation titles stored owner-only")
expect(partialReload.lastSessionTargets(pid: 200) == ["대화 A", "대화 B"],
       "partial evidence cannot change previous-session restore targets")
try! FileManager.default.removeItem(at: testDirectory)
print("PASS title history / session recovery \(passes) assertions")


// Normal Quit: native app may close windows one by one before terminating.
// Preserve previous two-window set when first window disappears briefly.
let quitDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("title-helper-normal-quit-\(UUID().uuidString)")
let quitFile = quitDir.appendingPathComponent("windows.json")
let normal = WindowSessionHistoryStore(file: quitFile)
let base = Date(timeIntervalSince1970: 10_000)
expect(normal.observe(pid: 410, titles: ["A", "B"], windowCount: 2,
                      now: base), "stable normal-quit baseline")
expect(normal.observe(pid: 410, titles: ["B"], windowCount: 1,
                      now: base.addingTimeInterval(1)), "delay sequential quit shrink")
expect(normal.snapshot.lastCompleteOpen == ["A", "B"],
       "normal app shutdown cannot overwrite two-window set")
expect(normal.observe(pid: 410, titles: ["B"], windowCount: 1,
                      now: base.addingTimeInterval(5)), "still inside grace period")
expect(normal.snapshot.lastCompleteOpen.count == 2,
       "partial quit sequence remains protected")
let afterQuit = WindowSessionHistoryStore(file: quitFile)
expect(afterQuit.observe(pid: 411, titles: ["New"], windowCount: 1,
                         now: base.addingTimeInterval(7)),
       "new PID sees preserved last complete window set")
expect(afterQuit.snapshot.previousSessionOpen == ["A", "B"],
       "normal Quit last two windows become prior session")
expect(!normal.hasPendingRestart(pid: 410),
       "same ChatGPT process must not display false missing windows")
expect(normal.hasPendingRestart(pid: 411),
       "restart without AX titles still displays saved previous windows")
expect(afterQuit.hasPendingRestart(pid: 412),
       "previous-session titles survive further PID changes")
expect(afterQuit.lastSessionTargets(pid: 412) == ["New"],
       "next restart targets immediately preceding PID, not older session")
expect(afterQuit.recoverable(excluding: [], pid: 412) == ["New"],
       "pending restart sidecar shows latest session")
expect(afterQuit.recoverable(excluding: ["New"], pid: 412).isEmpty,
       "already-open latest conversation is not duplicated")
expect(afterQuit.lastSessionTargets(pid: 411) == ["A", "B"],
       "same PID retains prior-session recovery contract")
let fileAttributes = try! FileManager.default.attributesOfItem(
    atPath: quitFile.path)
let mode = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
expect(mode & 0o777 == 0o600,
       "conversation-title history file must be accessible only by its owner")
// Earlier releases saved 0644; loading the same JSON must tighten mode.
try! FileManager.default.setAttributes(
    [.posixPermissions: 0o644], ofItemAtPath: quitFile.path)
let migration = WindowSessionHistoryStore(file: quitFile)
let migratedMode = (try! FileManager.default.attributesOfItem(
    atPath: quitFile.path)[.posixPermissions] as! NSNumber).intValue
expect(migratedMode & 0o777 == 0o600,
       "existing history file migrated from 0644 to private mode")
expect(migration.snapshot.previousSessionOpen == ["A", "B"] &&
       migration.snapshot.lastCompleteOpen == ["New"],
       "permissions migration never corrupts saved previous or active session")
expect(afterQuit.lastSessionTargets(pid: 411) == ["A", "B"],
       "last session targets exclude historical unrelated chats")
let steadyClose = WindowSessionHistoryStore(
    file: quitDir.appendingPathComponent("steady.json"))
expect(steadyClose.observe(pid: 420, titles: ["X", "Y"], windowCount: 2,
                           now: base), "stable-close starts with two")
expect(steadyClose.observe(pid: 420, titles: ["Y"], windowCount: 1,
                           now: base.addingTimeInterval(1)),
       "intentional shrink initially held")
expect(steadyClose.observe(pid: 420, titles: ["Y"], windowCount: 1,
                           now: base.addingTimeInterval(14)),
       "stable 13s intentional single window accepted")
expect(steadyClose.snapshot.lastCompleteOpen == ["Y"],
       "long-lived window close eventually saved")
try! FileManager.default.removeItem(at: quitDir)

// Bulk restore controller: stable order, already-open suppression, cancel after
// the in-flight action, no automatic retry or repeated native menu activity.
let queue = WindowSessionRestoreQueue()
var seenActions:[String]=[]
var reports:[WindowSessionRestoreQueue.Progress]=[]
queue.onProgress = {reports.append($0)}
let started=queue.start(
    titles:["A","B","A","C"], alreadyOpen:["B"]) { title, done in
    seenActions.append(title)
    done(true,"restored")
}
expect(started, "bulk action accepted")
expect(queue.isRunning, "queue stays active while waiting between items")
expect(seenActions == ["A"], "queue starts one title only")
expect(!queue.start(titles:["Z"],alreadyOpen:[],action:{_,_ in}),
       "second restore cannot overlap")
RunLoop.main.run(until: Date().addingTimeInterval(1.2))
expect(seenActions == ["A","C"], "preserve session order, skip open/duplicates")
expect(!queue.isRunning, "queue finishes after all unique missing titles")
expect(reports.last?.finished == 2 && reports.last?.total == 2,
       "bulk final counters correct")
let cancelQueue=WindowSessionRestoreQueue()
var pending: ((Bool,String) -> Void)?
var startedTitles:[String]=[]
expect(cancelQueue.start(titles:["A","B","C"],alreadyOpen:[]) { t, completion in
    startedTitles.append(t)
    pending=completion
}, "new queue accepted")
cancelQueue.cancel()
pending?(true,"done")
RunLoop.main.run(until: Date().addingTimeInterval(0.65))
expect(startedTitles == ["A"], "cancel prevents all later native actions")
expect(!cancelQueue.isRunning, "cancelled queue reaches terminal state")
print("PASS native last-session + batch restore \(passes) assertions")


// Late Chromium/AX title updates must not generate a false restore failure.
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 1.4, expectedCount: 3, actualCount: 3,
    newWindowTitleMatched: false, originalsRetained: true) == .pending,
    "1.4-second generic window remains pending, not failed")
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 8.0, expectedCount: 3, actualCount: 3,
    newWindowTitleMatched: true, originalsRetained: true) == .success,
    "late target title means success when originals are retained")
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 15.5, expectedCount: 3, actualCount: 3,
    newWindowTitleMatched: false, originalsRetained: true) == .pending,
    "wait for slow AX title up to timeout")
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 16.1, expectedCount: 3, actualCount: 3,
    newWindowTitleMatched: false, originalsRetained: true) == .failure,
    "unresolved title after deadline is failure")
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 8.0, expectedCount: 3, actualCount: 3,
    newWindowTitleMatched: true, originalsRetained: false) == .pending,
    "never claim success if an original window disappeared")
expect(WindowRestoreVerificationPolicy.decide(
    elapsed: 16.1, expectedCount: 3, actualCount: 4,
    newWindowTitleMatched: true, originalsRetained: true) == .failure,
    "unexpected extra windows do not silently pass")
print("PASS asynchronous restore verification policy \(passes) assertions")
