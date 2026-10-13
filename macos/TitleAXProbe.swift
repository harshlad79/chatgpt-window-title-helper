import AppKit
import ApplicationServices
import Foundation

// Diagnostic only. No title mutation, ChatGPT signals, or inspector connection.
private func get(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &out) == .success ? out : nil
}
private func text(_ element: AXUIElement, _ key: String) -> String {
    get(element, key) as? String ?? ""
}
private func findWebArea(_ root: AXUIElement) -> AXUIElement? {
    var queue = [root]
    var index = 0
    while index < queue.count && index < 600 {
        let element = queue[index]
        index += 1
        if text(element, kAXRoleAttribute) == "AXWebArea" { return element }
        if let children = get(element, kAXChildrenAttribute) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return nil
}
private func now() -> String { ISO8601DateFormatter().string(from: Date()) }

private final class Recorder {
    static let shared = Recorder()
    private let lock = NSLock()
    private var handle: FileHandle?
    private init() {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/ChatGPTTitleHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("title-ax-probe-current.log")
        try? Data().write(to: file, options: .atomic)
        handle = try? FileHandle(forWritingTo: file)
    }
    func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = message + "\n"
        print(message)
        if let data = line.data(using: .utf8) { try? handle?.write(contentsOf: data) }
    }
}
private func emit(_ message: String) { Recorder.shared.write(message) }

private let callback: AXObserverCallback = { _, element, notification, _ in
    // Event-only callback. Never walk the accessibility tree here.
    emit("\(now()) event=\(notification) elementHash=\(CFHash(element))")
}

func run() {
    let seconds = CommandLine.arguments.count > 1
        ? min(900, max(0, Int(CommandLine.arguments[1]) ?? 0)) : 900
    emit("START=\(now()) trusted=\(AXIsProcessTrusted()) seconds=\(seconds)")
    guard AXIsProcessTrusted() else {
        emit("BLOCKED: Accessibility permission required for probe process")
        return
    }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.openai.codex"
    }) else { print("BLOCKED: ChatGPT not running"); return }
    let pid = app.processIdentifier
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 1)
    var observerValue: AXObserver?
    let createStatus = AXObserverCreate(pid, callback, &observerValue)
    emit("OBSERVER_STATUS=\(createStatus.rawValue) PID=\(pid)")
    guard createStatus == .success, let observer = observerValue else { return }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    let appStatus = AXObserverAddNotification(
        observer, root, kAXWindowCreatedNotification as CFString, nil)
    emit("SUB_APP_WINDOW_CREATED=\(appStatus.rawValue)")
    guard let windows = get(root, kAXWindowsAttribute) as? [AXUIElement] else {
        emit("BLOCKED: AXWindows unavailable")
        return
    }
    emit("WINDOW_COUNT=\(windows.count)")
    for (idx, window) in windows.enumerated() {
        let caption = text(window, kAXTitleAttribute)
        var isSettable = DarwinBoolean(false)
        let setter = AXUIElementIsAttributeSettable(
            window, kAXTitleAttribute as CFString, &isSettable)
        emit("WINDOW_\(idx) HASH=\(CFHash(window)) TITLE=\(caption) SETTABLE=\(isSettable.boolValue) SETTER_STATUS=\(setter.rawValue)")
        let status = AXObserverAddNotification(
            observer, window, kAXTitleChangedNotification as CFString, nil)
        emit("SUB_WINDOW_TITLE_\(idx)=\(status.rawValue)")
        if let webArea = findWebArea(window) {
            emit("WEB_\(idx) HASH=\(CFHash(webArea)) TITLE=\(text(webArea,kAXTitleAttribute))")
            let titleStatus = AXObserverAddNotification(
                observer, webArea, kAXTitleChangedNotification as CFString, nil)
            emit("SUB_WEB_TITLE_\(idx)=\(titleStatus.rawValue)")
            let valueStatus = AXObserverAddNotification(
                observer, webArea, kAXValueChangedNotification as CFString, nil)
            emit("SUB_WEB_VALUE_\(idx)=\(valueStatus.rawValue)")
        }
    }
    if seconds > 0 {
        RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(seconds)))
    }
    emit("DONE=\(now())")
}
run()
