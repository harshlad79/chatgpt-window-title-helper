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
private let callback: AXObserverCallback = { _, element, notification, _ in
    // Event-only callback. Never walk the accessibility tree here.
    print("\(now()) event=\(notification) elementHash=\(CFHash(element))")
    fflush(stdout)
}

func run() {
    let seconds = CommandLine.arguments.count > 1
        ? min(900, max(0, Int(CommandLine.arguments[1]) ?? 0)) : 0
    print("START=\(now()) trusted=\(AXIsProcessTrusted()) seconds=\(seconds)")
    guard AXIsProcessTrusted() else {
        print("BLOCKED: Accessibility permission required for probe process")
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
    print("OBSERVER_STATUS=\(createStatus.rawValue) PID=\(pid)")
    guard createStatus == .success, let observer = observerValue else { return }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    let appStatus = AXObserverAddNotification(
        observer, root, kAXWindowCreatedNotification as CFString, nil)
    print("SUB_APP_WINDOW_CREATED=\(appStatus.rawValue)")
    guard let windows = get(root, kAXWindowsAttribute) as? [AXUIElement] else {
        print("BLOCKED: AXWindows unavailable")
        return
    }
    print("WINDOW_COUNT=\(windows.count)")
    for (idx, window) in windows.enumerated() {
        let caption = text(window, kAXTitleAttribute)
        var isSettable = DarwinBoolean(false)
        let setter = AXUIElementIsAttributeSettable(
            window, kAXTitleAttribute as CFString, &isSettable)
        print("WINDOW_\(idx) HASH=\(CFHash(window)) TITLE=\(caption) SETTABLE=\(isSettable.boolValue) SETTER_STATUS=\(setter.rawValue)")
        let status = AXObserverAddNotification(
            observer, window, kAXTitleChangedNotification as CFString, nil)
        print("SUB_WINDOW_TITLE_\(idx)=\(status.rawValue)")
        if let webArea = findWebArea(window) {
            print("WEB_\(idx) HASH=\(CFHash(webArea)) TITLE=\(text(webArea,kAXTitleAttribute))")
            let titleStatus = AXObserverAddNotification(
                observer, webArea, kAXTitleChangedNotification as CFString, nil)
            print("SUB_WEB_TITLE_\(idx)=\(titleStatus.rawValue)")
            let valueStatus = AXObserverAddNotification(
                observer, webArea, kAXValueChangedNotification as CFString, nil)
            print("SUB_WEB_VALUE_\(idx)=\(valueStatus.rawValue)")
        }
    }
    fflush(stdout)
    if seconds > 0 {
        RunLoop.current.run(until: Date().addingTimeInterval(TimeInterval(seconds)))
    }
    print("DONE=\(now())")
}
run()
