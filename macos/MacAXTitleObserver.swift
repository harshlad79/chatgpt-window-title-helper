import AppKit
import ApplicationServices

// Event callbacks only queue keys. AX tree traversal happens later on AppKit's
// serial main runloop, never inside an AX notification callback.
final class MacAXTitleObserver {
    private struct Watch {
        let element: AXUIElement
        let notification: String
        let windowID: String?
        let isTitleElement: Bool
    }

    private let observer: AXObserver
    private let app: AXUIElement
    private let onChanged: (String?, Bool) -> Void
    private var watching: [String: Watch] = [:]
    private var desired: Set<String> = []

    private static let callback: AXObserverCallback = { _, element, note, pointer in
        guard let pointer else { return }
        let selfRef = Unmanaged<MacAXTitleObserver>.fromOpaque(pointer)
            .takeUnretainedValue()
        let token = <redacted>        guard let watch = selfRef.watching[token] else { return }
        TitleHelperDiagnostics.shared.record(
            "ax-event type=\(note) targeted=\(watch.windowID != nil)")
        selfRef.onChanged(watch.windowID, watch.isTitleElement)
    }

    init?(pid: pid_t, app: AXUIElement,
          onChanged: @escaping (String?, Bool) -> Void) {
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success,
              let created else { return nil }
        self.observer = created
        self.app = app
        self.onChanged = onChanged
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes
        )
    }

    private func add(_ element: AXUIElement, _ note: String,
                     _ window: String?, titleElement: Bool = false) {
        let token = <redacted>        desired.insert(token)
        if watching[token] != nil { return }
        let result = AXObserverAddNotification(
            observer, element, note as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if result == .success {
            watching[token] = Watch(
                element: element, notification: note,
                windowID: window, isTitleElement: titleElement
            )
        } else {
            TitleHelperDiagnostics.shared.record(
                "ax-subscribe-failure note=\(note) code=\(result.rawValue)")
        }
    }

    func beginDiscovery() {
        desired.removeAll(keepingCapacity: true)
        for notification in [
            kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification, kAXFocusedUIElementChangedNotification
        ] {
            add(app, notification, nil)
        }
    }

    func watchWindow(_ window: AXUIElement, id: String) {
        for notification in [
            kAXTitleChangedNotification, kAXMovedNotification,
            kAXResizedNotification, kAXLayoutChangedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification
        ] {
            add(window, notification, id)
        }
    }

    func watchTitle(_ webArea: AXUIElement?, buttons: [AXUIElement], id: String) {
        // Read-only subscription on all exact matching elements, even if the
        // title is a single character. Unlike AXPress, no unique button is
        // required; two matching title controls are expected on ChatGPT.
        for element in ([webArea].compactMap { $0 } + buttons.prefix(4)) {
            for notification in [
                kAXTitleChangedNotification, kAXValueChangedNotification
            ] {
                add(element, notification, id, titleElement: true)
            }
        }
        if let webArea {
            add(webArea, kAXLayoutChangedNotification, id,
                titleElement: true)
        }
    }

    func finishDiscovery() {
        TitleHelperDiagnostics.shared.record(
            "ax-subscriptions active=\(watching.count) desired=\(desired.count)")
        // Stale remote accessibility elements may refuse unsubscription.
        // Always discard local references; never hold defunct AX nodes forever.
        for token in watching.keys.filter({ !desired.contains($0) }) {
            guard let old = watching.removeValue(forKey: token) else { continue }
            _ = AXObserverRemoveNotification(
                observer, old.element, old.notification as CFString
            )
        }
    }

    func stop() {
        for (_, old) in watching {
            _ = AXObserverRemoveNotification(
                observer, old.element, old.notification as CFString
            )
        }
        watching.removeAll()
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes
        )
    }

    deinit { stop() }
}
