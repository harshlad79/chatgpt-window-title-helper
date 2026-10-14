import AppKit
import ApplicationServices
import CryptoKit
import Foundation

// Read-only AX tree and event observer. Never reads message text into logs.
private let bundleID = "com.openai.codex"
private func now() -> String { ISO8601DateFormatter().string(from: Date()) }
private func digest(_ input: String) -> String {
    let data = SHA256.hash(data: Data(input.utf8))
    return data.prefix(6).map { String(format: "%02x", $0) }.joined()
}
private final class Recorder {
    static let shared = Recorder()
    private let lock = NSLock()
    private let handle: FileHandle?
    private init() {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/ChatGPTTitleHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("title-ax-probe-current.log")
        try? Data().write(to: file, options: .atomic)
        handle = try? FileHandle(forWritingTo: file)
    }
    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let full = now() + " " + line + "\n"
        print(full, terminator: "")
        if let data = full.data(using: .utf8) { try? handle?.write(contentsOf: data) }
    }
}
private func log(_ s: String) { Recorder.shared.write(s) }
private func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &out) == .success ? out : nil
}
private func string(_ e: AXUIElement, _ attribute: String) -> String {
    (read(e, attribute) as? String) ?? ""
}
private func label(_ value: String) -> String {
    if value.isEmpty { return "-" }
    return "len\(value.count):sha\(digest(value))"
}
private func key(_ e: AXUIElement) -> String { String(CFHash(e)) }
private struct Entry {
    let element: AXUIElement
    let depth: Int
    let parent: String
}
private let callback: AXObserverCallback = { _, element, note, _ in
    log("event name=\(note) element=\(key(element))")
}

private final class Probe {
    private let appElement: AXUIElement
    private let observer: AXObserver
    private var notified: Set<String> = []
    private var previous: [String: String] = [:]
    private var scans = 0
    private let maxNodes = 1000
    private let maxPerWindow = 420
    private let maxSubscriptions = 400
    private var subscriptionCount = 0

    init(app: AXUIElement, observer: AXObserver) {
        appElement = app
        self.observer = observer
    }

    private func subscribe(_ e: AXUIElement, _ notification: String, _ context: String) {
        guard subscriptionCount < maxSubscriptions else { return }
        let token = key(e) + ":" + notification
        guard notified.insert(token).inserted else { return }
        let status = AXObserverAddNotification(observer, e, notification as CFString, nil)
        if status == .success {
            subscriptionCount += 1
        } else {
            notified.remove(token)
            // Unsupported notification (-25205) can occur on ordinary controls.
            if scans == 0 && context == "window" {
                log("subscribe-fail note=\(notification) status=\(status.rawValue)")
            }
        }
    }

    private func subscribeApp() {
        for event in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                      kAXMainWindowChangedNotification, kAXFocusedUIElementChangedNotification] {
            subscribe(appElement, event, "application")
        }
    }

    func scan() {
        let initial = scans == 0
        scans += 1
        subscribeApp()
        guard let windows = read(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
            log("scan=\(scans) status=unavailable-windows")
            return
        }
        log("scan=\(scans) windows=\(windows.count) subscriptions=\(subscriptionCount)")
        var allNodes = 0
        var allChanges = 0
        for (windowIndex, window) in windows.enumerated() {
            if windowIndex >= 12 { break }
            let winHash = key(window)
            subscribe(window, kAXTitleChangedNotification, "window")
            subscribe(window, kAXLayoutChangedNotification, "window")
            subscribe(window, kAXResizedNotification, "window")
            var queue = [Entry(element: window, depth: 0, parent: "-")]
            var offset = 0
            var roles: [String: Int] = [:]
            var accessibleLabels = 0
            while offset < queue.count && offset < maxPerWindow && allNodes < maxNodes {
                let current = queue[offset]
                offset += 1
                allNodes += 1
                let e = current.element
                let role = string(e, kAXRoleAttribute)
                let subtype = string(e, kAXSubroleAttribute)
                let title = string(e, kAXTitleAttribute)
                let desc = string(e, kAXDescriptionAttribute)
                let identifier = string(e, kAXIdentifierAttribute)
                let valueObject = read(e, kAXValueAttribute)
                let value = (valueObject as? String) ?? ""
                let hash = key(e)
                roles[role, default: 0] += 1
                let state = role + "/" + subtype + "/" + label(title) + "/" + label(value) + "/" + label(desc) + "/" + identifier
                if let old = previous[hash], old != state {
                    allChanges += 1
                    log("tree-diff window=\(windowIndex) node=\(hash) role=\(role) oldDigest=\(digest(old)) newDigest=\(digest(state))")
                }
                previous[hash] = state
                if !title.isEmpty || !value.isEmpty || !desc.isEmpty {
                    accessibleLabels += 1
                    if initial && accessibleLabels <= 100 {
                        log("node window=\(windowIndex) depth=\(current.depth) parent=\(current.parent) hash=\(hash) role=\(role) subrole=\(subtype) title=\(label(title)) value=\(label(value)) desc=\(label(desc)) ident=\(identifier.prefix(80))")
                    }
                }
                if initial && offset <= 20 {
                    log("structure window=\(windowIndex) depth=\(current.depth) parent=\(current.parent) hash=\(hash) role=\(role) subrole=\(subtype)")
                }
                if current.depth <= 11 {
                    let canSubscribe = !title.isEmpty || !value.isEmpty || !desc.isEmpty ||
                        ["AXButton", "AXStaticText", "AXTextField", "AXTextArea",
                         "AXWebArea", "AXGroup", "AXWindow"].contains(role)
                    if canSubscribe && subscriptionCount < maxSubscriptions {
                        subscribe(e, kAXTitleChangedNotification, "node")
                        subscribe(e, kAXValueChangedNotification, "node")
                        if ["AXWindow", "AXWebArea", "AXGroup"].contains(role) {
                            subscribe(e, kAXLayoutChangedNotification, "node")
                            subscribe(e, kAXSelectedChildrenChangedNotification, "node")
                        }
                    }
                    let children = (read(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
                    for child in children.prefix(120) {
                        if queue.count >= maxPerWindow { break }
                        queue.append(Entry(element: child, depth: current.depth + 1, parent: hash))
                    }
                }
            }
            log("window-summary index=\(windowIndex) hash=\(winHash) scanned=\(offset) labels=\(accessibleLabels) queued=\(queue.count) roles=\(roles.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))")
        }
        log("scan-done count=\(scans) nodes=\(allNodes) diffs=\(allChanges) subscriptions=\(subscriptionCount)")
    }
}

private func run() {
    let seconds = CommandLine.arguments.count > 1
        ? min(900, max(0, Int(CommandLine.arguments[1]) ?? 0)) : 900
    log("probe-version=2 trusted=\(AXIsProcessTrusted()) seconds=\(seconds)")
    guard AXIsProcessTrusted() else { log("blocked: accessibility permission"); return }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
    }) else { log("blocked: ChatGPT app not running"); return }
    let pid = app.processIdentifier
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 0.6)
    var observer: AXObserver?
    let status = AXObserverCreate(pid, callback, &observer)
    log("observer-create status=\(status.rawValue) pid=\(pid)")
    guard status == .success, let watcher = observer else { return }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(watcher), .defaultMode)
    let probe = Probe(app: root, observer: watcher)
    probe.scan()
    if seconds > 0 {
        let timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { _ in probe.scan() }
        RunLoop.current.add(timer, forMode: .common)
        RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(seconds)))
        timer.invalidate()
    }
    log("probe-finished")
}
run()
