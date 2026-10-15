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
    // Read only the event source's scalar attributes, not its subtree.
    // This permits exact title fingerprint correlation, even for one character.
    if note as String == (kAXTitleChangedNotification as String) {
        let role = string(element, kAXRoleAttribute)
        let title = string(element, kAXTitleAttribute)
        log("event name=\(note) element=\(key(element)) role=\(role) title=\(label(title))")
    } else {
        log("event name=\(note) element=\(key(element))")
    }
}

private final class Probe {
    private let appElement: AXUIElement
    private let observer: AXObserver
    private struct Subscription {
        let element: AXUIElement
        let notification: String
    }
    private var active: [String: Subscription] = [:]
    private var desired: Set<String> = []
    private var previous: [String: String] = [:]
    private var previousTitleCandidates: Set<String> = []
    private var scans = 0
    private let maxNodes = 1000
    private let maxPerWindow = 420
    private let maxSubscriptions = 400
    private var subscriptionCount: Int { active.count }

    init(app: AXUIElement, observer: AXObserver) {
        appElement = app
        self.observer = observer
    }

    private func subscribe(_ e: AXUIElement, _ notification: String, _ context: String) {
        let token = <redacted> + ":" + notification
        desired.insert(token)
        if active[token] != nil { return }
        guard active.count < maxSubscriptions else {
            if context == "title-candidate" {
                log("subscription-cap reached role=title-candidate")
            }
            return
        }
        let status = AXObserverAddNotification(observer, e, notification as CFString, nil)
        if status == .success {
            active[token] = Subscription(element: e, notification: notification)
            if context == "title-candidate" {
                log("title-subscription element=\(key(e)) note=\(notification) status=0")
            }
        } else if context == "title-candidate" {
            // Some AX elements do not support each of these event types.
            log("title-subscription element=\(key(e)) note=\(notification) status=\(status.rawValue)")
        }
    }

    private func pruneSubscriptions() {
        var removed = 0
        var invalidated: [Int32: Int] = [:]
        for token in active.keys.filter({ !desired.contains($0) }) {
            guard let old = active.removeValue(forKey: token) else { continue }
            let status = AXObserverRemoveNotification(
                observer, old.element, old.notification as CFString)
            if status == .success || status == .notificationNotRegistered {
                removed += 1
            } else {
                // This usually indicates an AX element that has disappeared
                // during navigation. Release our local reference regardless.
                // A remote unsubscribe is not claimed on a failed operation.
                invalidated[status.rawValue, default: 0] += 1
            }
        }
        if removed > 0 || !invalidated.isEmpty {
            let errors = invalidated.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: ",")
            log("subscription-prune removed=\(removed) invalidated=\(errors) remaining=\(subscriptionCount)")
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
        desired.removeAll(keepingCapacity: true)
        subscribeApp()
        guard let windows = read(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
            log("scan=\(scans) status=unavailable-windows")
            return
        }
        log("scan=\(scans) windows=\(windows.count) subscriptions=\(subscriptionCount)")
        var allNodes = 0
        var allChanges = 0
        var titleCandidates: Set<String> = []
        for (windowIndex, window) in windows.enumerated() {
            if windowIndex >= 12 { break }
            let winHash = key(window)
            subscribe(window, kAXTitleChangedNotification, "window")
            subscribe(window, kAXLayoutChangedNotification, "window")
            subscribe(window, kAXResizedNotification, "window")
            var queue = [Entry(element: window, depth: 0, parent: "-")]
            if windowIndex == 0,
               let value = read(appElement, kAXFocusedUIElementAttribute),
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                let focused = unsafeBitCast(value, to: AXUIElement.self)
                queue.append(Entry(element: focused, depth: 0, parent: "AXFocusedUIElement"))
            }
            var seen: Set<String> = []
            var offset = 0
            var roles: [String: Int] = [:]
            var accessibleLabels = 0
            while offset < queue.count && offset < maxPerWindow && allNodes < maxNodes {
                let current = queue[offset]
                offset += 1
                allNodes += 1
                let e = current.element
                let nodeHash = key(e)
                if !seen.insert(nodeHash).inserted { continue }
                let role = string(e, kAXRoleAttribute)
                let subtype = string(e, kAXSubroleAttribute)
                let title = string(e, kAXTitleAttribute)
                let desc = string(e, kAXDescriptionAttribute)
                let identifier = string(e, kAXIdentifierAttribute)
                let valueObject = read(e, kAXValueAttribute)
                let value = (valueObject as? String) ?? ""
                let hash = key(e)
                roles[role, default: 0] += 1
                if ["AXWebArea", "AXHeading", "AXStaticText", "AXButton",
                    "AXTextField", "AXTextArea"].contains(role) {
                    if !title.isEmpty { titleCandidates.insert("\(role):\(label(title))") }
                    if !value.isEmpty && role != "AXTextArea" {
                        titleCandidates.insert("\(role):\(label(value))")
                    }
                }
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
                if initial && offset <= 25 {
                    log("structure window=\(windowIndex) depth=\(current.depth) parent=\(current.parent) hash=\(hash) role=\(role) subrole=\(subtype)")
                    if current.depth >= 4 || current.parent == "AXFocusedUIElement" {
                        var names: CFArray?
                        let status = AXUIElementCopyAttributeNames(e, &names)
                        if status == .success, let attrs = names as? [String] {
                            log("attrs window=\(windowIndex) role=\(role) depth=\(current.depth) names=\(attrs.sorted().joined(separator: ","))")
                        }
                    }
                }
                if current.depth <= 11 {
                    // Subscribe all potentially title-bearing roles, regardless
                    // of text length (including one-character conversation titles).
                    // Avoid generic AXGroups, which previously exhausted the cap.
                    let isTitleCandidate = [
                        "AXWebArea", "AXButton", "AXHeading", "AXStaticText",
                        "AXTextField", "AXTextArea"
                    ].contains(role)
                    if isTitleCandidate {
                        subscribe(e, kAXTitleChangedNotification, "title-candidate")
                        subscribe(e, kAXValueChangedNotification, "title-candidate")
                        if role == "AXWebArea" {
                            subscribe(e, kAXLayoutChangedNotification, "webarea")
                        }
                    }
                    // Compare conventional and alternative AX subtree attributes.
                    // macOS/Electron may expose a focused element or visible subtree
                    // without listing it in AXChildren.
                    for source in [kAXChildrenAttribute, kAXVisibleChildrenAttribute,
                                   kAXContentsAttribute, "AXChildrenInNavigationOrder"] {
                        let children = (read(e, source) as? [AXUIElement]) ?? []
                        if initial && !children.isEmpty && source != kAXChildrenAttribute {
                            log("alternate-children window=\(windowIndex) role=\(role) depth=\(current.depth) source=\(source) count=\(children.count)")
                        }
                        for child in children.prefix(120) {
                            if queue.count >= maxPerWindow { break }
                            queue.append(Entry(element: child, depth: current.depth + 1, parent: hash))
                        }
                    }
                }
            }
            log("window-summary index=\(windowIndex) hash=\(winHash) scanned=\(offset) labels=\(accessibleLabels) queued=\(queue.count) roles=\(roles.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))")
        }
        if initial {
            log("candidate-baseline count=\(titleCandidates.count) fingerprints=\(titleCandidates.sorted().joined(separator: ","))")
        } else {
            let added = titleCandidates.subtracting(previousTitleCandidates)
            let removed = previousTitleCandidates.subtracting(titleCandidates)
            if !added.isEmpty || !removed.isEmpty {
                log("candidate-delta scan=\(scans) added=\(added.sorted().joined(separator: ",")) removed=\(removed.sorted().joined(separator: ","))")
            }
        }
        previousTitleCandidates = titleCandidates
        pruneSubscriptions()
        log("scan-done count=\(scans) nodes=\(allNodes) diffs=\(allChanges) titleCandidates=\(titleCandidates.count) subscriptions=\(subscriptionCount)")
    }
}

// Read-only action capability census for a specifically named ChatGPT conversation.
// Uses the same signed TCC principal as the watcher. It NEVER performs an action.
private func inspectTitleActions(expectedTitle: String, pressMatchedButton: Bool = false,
                                 temporaryValue: String? = nil, keyboardValue: String? = nil,
                                 raiseTarget: Bool = false, roundTrip: String? = nil) {
    guard AXIsProcessTrusted() else {
        log("AX_ACTION_INSPECT blocked=accessibility")
        return
    }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
    }) else {
        log("AX_ACTION_INSPECT blocked=chatgpt-not-running")
        return
    }
    let pid = app.processIdentifier
    log("AX_ACTION_INSPECT postEventPermission=\(CGPreflightPostEventAccess()) appActive=\(app.isActive)")
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 0.5)
    guard let windows = read(root, kAXWindowsAttribute) as? [AXUIElement] else {
        log("AX_ACTION_INSPECT blocked=windows-unavailable")
        return
    }
    let actionMode = roundTrip != nil ? "rename-and-restore" :
        (pressMatchedButton ? "press-title-button" :
        (keyboardValue != nil ? "keyboard-trial" :
        (temporaryValue != nil ? "axvalue-trial" :
        (raiseTarget ? "raise-title-window" : "readonly"))))
    log("AX_ACTION_INSPECT mode=\(actionMode) expected=\(label(expectedTitle)) windows=\(windows.count)")
    var matches: [(Int, AXUIElement)] = []
    func descend(_ top: AXUIElement, max: Int) -> [AXUIElement] {
        var queue = [top]
        var seen: Set<String> = []
        var result: [AXUIElement] = []
        var index = 0
        while index < queue.count && index < max {
            let e = queue[index]
            index += 1
            let id = key(e)
            if !seen.insert(id).inserted { continue }
            result.append(e)
            // Avoid four-way duplicate scanning: AXChildren is sufficient once
            // the Chromium tree is exposed; AXVisibleChildren is fallback only.
            let children = (read(e, kAXChildrenAttribute) as? [AXUIElement]) ??
                ((read(e, kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? [])
            for child in children.prefix(180) where queue.count < max {
                queue.append(child)
            }
        }
        return result
    }
    for (index, window) in windows.enumerated() where index < 20 {
        let nodes = descend(window, max: 1200)
        let titles = nodes.filter {
            string($0, kAXRoleAttribute) == "AXWebArea" &&
            string($0, kAXTitleAttribute) == expectedTitle
        }
        log("AX_ACTION_WINDOW index=\(index) nodes=\(nodes.count) exactWebAreaMatches=\(titles.count)")
        if !titles.isEmpty { matches.append((index, window)) }
    }
    guard matches.count == 1 else {
        log("AX_ACTION_INSPECT blocked=expected-title-window-ambiguous matches=\(matches.count)")
        return
    }
    let (index, targetWindow) = matches[0]
    var targetActions: CFArray?
    let targetStatus = AXUIElementCopyActionNames(targetWindow, &targetActions)
    let windowActions = targetStatus == .success ?
        ((targetActions as? [String]) ?? []).sorted() : []
    let focusedWindowValue = read(root, kAXFocusedWindowAttribute)
    let isTargetFocused = focusedWindowValue.map {
        CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, targetWindow)
    } ?? false
    var focusedWindowHash = "unknown"
    if let v = focusedWindowValue, CFGetTypeID(v) == AXUIElementGetTypeID() {
        focusedWindowHash = key(unsafeBitCast(v, to: AXUIElement.self))
    }
    log("AX_TARGET_WINDOW hash=\(key(targetWindow)) focused=\(isTargetFocused) focusedWindow=\(focusedWindowHash) actions=\(windowActions.joined(separator: ","))")
    if let roundTrip {
        guard !roundTrip.isEmpty, roundTrip != expectedTitle,
              CGPreflightPostEventAccess() else {
            log("AX_ROUNDTRIP blocked=invalid-input-or-permission")
            return
        }
        if !app.isActive {
            let activated = app.activate()
            Thread.sleep(forTimeInterval: 0.4)
            log("AX_ROUNDTRIP activationRequested=\(activated) activeNow=\(app.isActive)")
        }
        guard app.isActive else {
            log("AX_ROUNDTRIP blocked=chatgpt-app-inactive")
            return
        }
        let focusBeforeRaise = read(root, kAXFocusedWindowAttribute)
        let targetCurrentlyFocused = focusBeforeRaise.map {
            CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, targetWindow)
        } ?? false
        if !targetCurrentlyFocused {
            guard windowActions.contains(kAXRaiseAction as String),
                  AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString) == .success else {
                log("AX_ROUNDTRIP blocked=cannot-raise-target-window")
                return
            }
            Thread.sleep(forTimeInterval: 0.35)
        }
        guard let focusCheck = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(focusCheck) == AXUIElementGetTypeID(),
              CFEqual(focusCheck, targetWindow) else {
            log("AX_ROUNDTRIP blocked=target-window-not-focused")
            return
        }
        func focused() -> Bool {
            guard app.isActive, let w = read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(w) == AXUIElementGetTypeID() else { return false }
            return CFEqual(w, targetWindow)
        }
        func matchingInput(_ value: String) -> AXUIElement? {
            let fields = descend(targetWindow, max: 1600).filter {
                string($0, kAXRoleAttribute) == "AXTextField" &&
                string($0, kAXValueAttribute) == value
            }
            guard fields.count == 1 else { return nil }
            return fields[0]
        }
        func hasTitle(_ value: String) -> Bool {
            let found = descend(targetWindow, max: 1600).filter {
                string($0, kAXRoleAttribute) == "AXWebArea" &&
                string($0, kAXTitleAttribute) == value
            }
            return found.count == 1
        }
        func sendKey(code: CGKeyCode, flags: CGEventFlags = [],
                     unicode: String? = nil) -> Bool {
            guard focused(),
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
            else { return false }
            down.flags = flags
            up.flags = flags
            if let unicode {
                let units = Array(unicode.utf16)
                guard !units.isEmpty else { return false }
                units.withUnsafeBufferPointer { chars in
                    guard let p = chars.baseAddress else { return }
                    down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: p)
                    up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: p)
                }
            }
            down.postToPid(pid)
            up.postToPid(pid)
            return true
        }
        func replaceText(_ field: AXUIElement, _ value: String) -> Bool {
            guard focused(),
                  (read(field, kAXFocusedAttribute) as? NSNumber)?.boolValue == true else {
                return false
            }
            guard sendKey(code: 0, flags: .maskCommand),
                  sendKey(code: 0, unicode: value) else { return false }
            Thread.sleep(forTimeInterval: 0.35)
            return string(field, kAXValueAttribute) == value
        }
        func waitForTitle(_ value: String) -> Bool {
            for _ in 0..<15 {
                if hasTitle(value) { return true }
                Thread.sleep(forTimeInterval: 0.2)
            }
            return false
        }
        func openEditor(_ value: String) -> AXUIElement? {
            if let field = matchingInput(value),
               (read(field, kAXFocusedAttribute) as? NSNumber)?.boolValue == true {
                return field
            }
            let buttons = descend(targetWindow, max: 1600).filter {
                string($0, kAXRoleAttribute) == "AXButton" &&
                string($0, kAXTitleAttribute) == value
            }
            guard buttons.count == 1,
                  AXUIElementPerformAction(buttons[0], kAXPressAction as CFString) == .success
            else { return nil }
            Thread.sleep(forTimeInterval: 0.35)
            return matchingInput(value)
        }
        // Local, owner-only recovery record in case the agent is interrupted.
        let rollback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/ChatGPTTitleHelper/title-probe-rollback.txt")
        do {
            try Data(expectedTitle.utf8).write(to: rollback, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: rollback.path)
        } catch {
            log("AX_ROUNDTRIP blocked=cannot-preserve-original-title")
            return
        }
        log("AX_ROUNDTRIP start original=\(label(expectedTitle)) temporary=\(label(roundTrip))")
        // Restore is attempted even if the first commit cannot be verified.
        guard let originalField = openEditor(expectedTitle),
              replaceText(originalField, roundTrip) else {
            if let field = matchingInput(roundTrip) { _ = replaceText(field, expectedTitle) }
            log("AX_ROUNDTRIP blocked=write-temporary-failed")
            return
        }
        guard sendKey(code: 0x24) else {
            _ = replaceText(originalField, expectedTitle)
            log("AX_ROUNDTRIP blocked=commit-keystroke-failed")
            return
        }
        let committed = waitForTitle(roundTrip)
        log("AX_ROUNDTRIP temporaryCommitted=\(committed)")
        // If the editor retained the temporary value without committing,
        // restore the visible field first; do not presume success.
        if !committed {
            if let field = matchingInput(roundTrip) {
                _ = replaceText(field, expectedTitle)
                _ = sendKey(code: 0x24)
            }
            let originalStill = waitForTitle(expectedTitle)
            log("AX_ROUNDTRIP rollbackAfterCommitFailure=\(originalStill)")
            return
        }
        guard focused() || (windowActions.contains(kAXRaiseAction as String)
              && AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString) == .success)
        else {
            log("AX_ROUNDTRIP blocked=lost-target-focus-after-rename")
            return
        }
        Thread.sleep(forTimeInterval: 0.25)
        guard let renamedField = openEditor(roundTrip),
              replaceText(renamedField, expectedTitle),
              sendKey(code: 0x24) else {
            log("AX_ROUNDTRIP blocked=failed-to-restore-title-input")
            return
        }
        let restored = waitForTitle(expectedTitle)
        log("AX_ROUNDTRIP originalRestored=\(restored) final=\(label(restored ? expectedTitle : roundTrip))")
        if restored {
            try? FileManager.default.removeItem(at: rollback)
        }
        return
    }
    if raiseTarget {
        guard windowActions.contains(kAXRaiseAction as String) else {
            log("AX_TARGET_RAISE blocked=unsupported")
            return
        }
        let status = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        Thread.sleep(forTimeInterval: 0.4)
        let focused = read(root, kAXFocusedWindowAttribute)
        let nowFocused = focused.map {
            CFGetTypeID($0) == AXUIElementGetTypeID() && CFEqual($0, targetWindow)
        } ?? false
        log("AX_TARGET_RAISE status=\(status.rawValue) nowFocused=\(nowFocused) edited=false")
        return
    }
    if let keyboardValue {
        guard isTargetFocused else {
            log("AX_KEYBOARD_TRIAL blocked=target-window-not-focused")
            return
        }
        guard !keyboardValue.isEmpty, keyboardValue != expectedTitle,
              app.isActive else {
            log("AX_KEYBOARD_TRIAL blocked=invalid-input-or-app-inactive")
            return
        }
        let fields = descend(targetWindow, max: 1600).filter {
            string($0, kAXRoleAttribute) == "AXTextField" &&
            string($0, kAXValueAttribute) == expectedTitle
        }
        guard fields.count == 1,
              (read(fields[0], kAXFocusedAttribute) as? NSNumber)?.boolValue == true else {
            log("AX_KEYBOARD_TRIAL blocked=exact-focused-field-not-found count=\(fields.count)")
            return
        }
        let field = fields[0]
        func sendKey(code: CGKeyCode, flags: CGEventFlags = [],
                     unicode: String? = nil) -> Bool {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
            else { return false }
            down.flags = flags
            up.flags = flags
            if let unicode {
                let units = Array(unicode.utf16)
                units.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
            down.postToPid(pid)
            up.postToPid(pid)
            return true
        }
        func replaceText(_ replacement: String) -> Bool {
            sendKey(code: 0x00, flags: .maskCommand) &&
                sendKey(code: 0x00, unicode: replacement)
        }
        log("AX_KEYBOARD_TRIAL start expected=\(label(expectedTitle)) replacement=\(label(keyboardValue))")
        guard replaceText(keyboardValue) else {
            log("AX_KEYBOARD_TRIAL blocked=failed-to-create-event")
            return
        }
        Thread.sleep(forTimeInterval: 0.6)
        let observed = string(field, kAXValueAttribute)
        log("AX_KEYBOARD_TRIAL typed=\(label(observed)) matchesRequested=\(observed == keyboardValue)")
        // Always restore original UI contents, regardless of the first result.
        let restoreSent = replaceText(expectedTitle)
        Thread.sleep(forTimeInterval: 0.8)
        let final = string(field, kAXValueAttribute)
        let webTitles = descend(targetWindow, max: 1600)
            .filter { string($0, kAXRoleAttribute) == "AXWebArea" }
            .map { string($0, kAXTitleAttribute) }
        log("AX_KEYBOARD_TRIAL restoreSent=\(restoreSent) restored=\(final == expectedTitle) webAreaOriginal=\(webTitles.contains(expectedTitle)) saved=false")
        return
    }
    if let temporaryValue {
        guard isTargetFocused else {
            log("AX_FIELD_TRIAL blocked=target-window-not-focused")
            return
        }
        guard !temporaryValue.isEmpty, temporaryValue != expectedTitle else {
            log("AX_FIELD_TRIAL blocked=invalid-replacement")
            return
        }
        let fields = descend(targetWindow, max: 1600).filter {
            string($0, kAXRoleAttribute) == "AXTextField" &&
            string($0, kAXValueAttribute) == expectedTitle
        }
        guard fields.count == 1 else {
            log("AX_FIELD_TRIAL blocked=ambiguous-field matches=\(fields.count)")
            return
        }
        let field = fields[0]
        var writable = DarwinBoolean(false)
        let writableStatus = AXUIElementIsAttributeSettable(
            field, kAXValueAttribute as CFString, &writable)
        guard writableStatus == .success, writable.boolValue else {
            log("AX_FIELD_TRIAL blocked=value-not-writable")
            return
        }
        // A reversible input-only check; intentionally no Return, click, or
        // other commit gesture. The expected conversation window was checked.
        let written = AXUIElementSetAttributeValue(
            field, kAXValueAttribute as CFString, temporaryValue as CFString)
        let readback = string(field, kAXValueAttribute)
        log("AX_FIELD_TRIAL writeStatus=\(written.rawValue) valueAfter=\(label(readback)) matchesRequested=\(readback == temporaryValue)")
        Thread.sleep(forTimeInterval: 0.3)
        // Restore unconditionally even when the first write reported an error.
        let restored = AXUIElementSetAttributeValue(
            field, kAXValueAttribute as CFString, expectedTitle as CFString)
        Thread.sleep(forTimeInterval: 0.3)
        let finalValue = string(field, kAXValueAttribute)
        let webTitles = descend(targetWindow, max: 1600)
            .filter { string($0, kAXRoleAttribute) == "AXWebArea" }
            .map { string($0, kAXTitleAttribute) }
        log("AX_FIELD_TRIAL restoreStatus=\(restored.rawValue) finalValue=\(label(finalValue)) fieldRestored=\(finalValue == expectedTitle) windowOriginalTitle=\(webTitles.contains(expectedTitle)) committed=false")
        return
    }
    if pressMatchedButton {
        let exactButtons = descend(targetWindow, max: 1600).filter { e in
            guard string(e, kAXRoleAttribute) == "AXButton",
                  string(e, kAXTitleAttribute) == expectedTitle else { return false }
            var names: CFArray?
            let status = AXUIElementCopyActionNames(e, &names)
            return status == .success && ((names as? [String]) ?? []).contains(kAXPressAction as String)
        }
        guard exactButtons.count == 1 else {
            log("AX_TITLE_BUTTON blocked=ambiguous-match count=\(exactButtons.count) mutated=false")
            return
        }
        // Only press a button whose exact title matches the already validated
        // WebArea and was explicitly requested. Never press a destructive menu.
        let pressStatus = AXUIElementPerformAction(exactButtons[0], kAXPressAction as CFString)
        log("AX_TITLE_BUTTON pressStatus=\(pressStatus.rawValue) expected=\(label(expectedTitle))")
        guard pressStatus == .success else { return }
        Thread.sleep(forTimeInterval: 0.5)
        var afterElements = 0
        let updatedWindows = (read(root, kAXWindowsAttribute) as? [AXUIElement]) ?? windows
        for (wid, window) in updatedWindows.enumerated() where wid < 20 {
            for e in descend(window, max: 1300) {
                let role = string(e, kAXRoleAttribute)
                guard ["AXMenu", "AXMenuItem", "AXTextField", "AXTextArea",
                       "AXPopUpButton", "AXDialog", "AXSheet"].contains(role) else { continue }
                var names: CFArray?
                let status = AXUIElementCopyActionNames(e, &names)
                let actions = status == .success ? ((names as? [String]) ?? []) : []
                let t = string(e, kAXTitleAttribute)
                let d = string(e, kAXDescriptionAttribute)
                let v = string(e, kAXValueAttribute)
                var writable = DarwinBoolean(false)
                let w = AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &writable)
                log("AX_TITLE_MENU window=\(wid) role=\(role) title=\(label(t)) desc=\(label(d)) value=\(label(v)) actions=\(actions.joined(separator: ",")) writable=\(w == .success && writable.boolValue)")
                afterElements += 1
                if afterElements >= 75 { break }
            }
            if afterElements >= 75 { break }
        }
        log("AX_TITLE_BUTTON postClickMenuElements=\(afterElements) conversationRenamed=false")
        return
    }
    // Inspect the exact title edit field and its local controls before any
    // AXValue mutation. Do not derive save/cancel by guesswork or coordinates.
    let editFields = descend(targetWindow, max: 1600).filter {
        string($0, kAXRoleAttribute) == "AXTextField" &&
        string($0, kAXValueAttribute) == expectedTitle
    }
    log("AX_EDIT_CONTEXT exactFieldMatches=\(editFields.count)")
    if let field = editFields.first {
        var settable = DarwinBoolean(false)
        let focusedStatus = AXUIElementIsAttributeSettable(
            field, kAXFocusedAttribute as CFString, &settable)
        let focusedAttr = read(field, kAXFocusedAttribute) as? NSNumber
        let focusValue = read(root, kAXFocusedUIElementAttribute)
        let matchingFocused = focusValue.map {
            CFGetTypeID($0) == AXUIElementGetTypeID() &&
            CFEqual($0, field)
        } ?? false
        log("AX_EDIT_FOCUS actualFocused=\(focusedAttr?.boolValue.description ?? "unknown") globalFocusedSame=\(matchingFocused) focusWritable=\(focusedStatus == .success && settable.boolValue) appActive=\(app.isActive)")
    }
    for field in editFields.prefix(2) {
        var cursor: AXUIElement = field
        for level in 0..<3 {
            let role = string(cursor, kAXRoleAttribute)
            let childNodes = (read(cursor, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            log("AX_EDIT_PARENT level=\(level) role=\(role) hash=\(key(cursor)) children=\(childNodes.count)")
            for child in childNodes.prefix(35) {
                let role = string(child, kAXRoleAttribute)
                let title = string(child, kAXTitleAttribute)
                let desc = string(child, kAXDescriptionAttribute)
                var arr: CFArray?
                _ = AXUIElementCopyActionNames(child, &arr)
                let actions = (arr as? [String]) ?? []
                log("AX_EDIT_SIBLING level=\(level) role=\(role) title=\(label(title)) desc=\(label(desc)) actions=\(actions.joined(separator: ","))")
            }
            guard let parentValue = read(cursor, kAXParentAttribute),
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            cursor = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
    }
    var inspected = 0
    var editable = 0
    for e in descend(targetWindow, max: 1600) {
        let role = string(e, kAXRoleAttribute)
        let title = string(e, kAXTitleAttribute)
        let desc = string(e, kAXDescriptionAttribute)
        let value = string(e, kAXValueAttribute)
        var names: CFArray?
        let actionStatus = AXUIElementCopyActionNames(e, &names)
        let actions = actionStatus == .success
            ? ((names as? [String]) ?? []).sorted() : []
        var settable = DarwinBoolean(false)
        let valueRC = AXUIElementIsAttributeSettable(
            e, kAXValueAttribute as CFString, &settable)
        let canWrite = valueRC == .success && settable.boolValue
        if canWrite { editable += 1 }
        if actions.isEmpty && !canWrite { continue }
        // Do not log message text. Only title/description/value fingerprints.
        // No title-length filter: even a one-character control is included.
        if ["AXButton", "AXTextField", "AXTextArea", "AXWebArea",
             "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXLink"].contains(role) {
            inspected += 1
            log("AX_ACTION_ELEMENT window=\(index) hash=\(key(e)) role=\(role) title=\(label(title)) desc=\(label(desc)) value=\(label(value)) actions=\(actions.joined(separator: ",")) writableValue=\(canWrite)")
        }
        if inspected >= 240 { break }
    }
    log("AX_ACTION_INSPECT complete window=\(index) actionable=\(inspected) writableValueCount=\(editable) mutated=false")
}

// Read-only macOS Dock-caption feasibility census for an already-running
// ChatGPT. Never mutates AXTitle, user conversations, or application code.
private func inspectNativeWindowTitle() {
    log("AX_WINDOW_CAPTION mode=readonly trusted=\(AXIsProcessTrusted())")
    guard AXIsProcessTrusted() else {
        log("AX_WINDOW_CAPTION blocked=accessibility-not-trusted")
        return
    }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
    }) else {
        log("AX_WINDOW_CAPTION blocked=chatgpt-not-running")
        return
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 1.0)
    guard let windows = read(root, kAXWindowsAttribute) as? [AXUIElement] else {
        log("AX_WINDOW_CAPTION blocked=windows-unavailable")
        return
    }
    log("AX_WINDOW_CAPTION windows=\(windows.count)")
    for (i, window) in windows.prefix(20).enumerated() {
        let title = string(window, kAXTitleAttribute)
        var writable = DarwinBoolean(false)
        let rc = AXUIElementIsAttributeSettable(
            window, kAXTitleAttribute as CFString, &writable
        )
        var names: CFArray?
        let attrsRC = AXUIElementCopyAttributeNames(window, &names)
        let support = ((names as? [String]) ?? []).contains(
            kAXTitleAttribute as String
        )
        let labelText = label(title)
        let captionStatus = "AX_WINDOW_CAPTION index=\(i) windowTitle=\(labelText) "
        let settableStatus = "settableStatus=\(rc.rawValue) writable=\(writable.boolValue) "
        let attributeStatus = "attrsStatus=\(attrsRC.rawValue) titleAttributeSupported=\(support) mutated=false"
        log(captionStatus + settableStatus + attributeStatus)
    }
}

private func run() {
    if CommandLine.arguments.count == 2 &&
       CommandLine.arguments[1] == "inspect-window-title" {
        inspectNativeWindowTitle()
        return
    }
    if CommandLine.arguments.count > 1 &&
        ["inspect-actions", "open-title-button", "test-title-field",
         "test-title-keyboard", "raise-target-window",
         "rename-and-restore"].contains(CommandLine.arguments[1]) {
        let isTrial = ["test-title-field", "test-title-keyboard",
                       "rename-and-restore"].contains(CommandLine.arguments[1])
        guard CommandLine.arguments.count == (isTrial ? 4 : 3) else {
            log("AX_ACTION_INSPECT blocked=usage-requires-one-exact-title")
            return
        }
        inspectTitleActions(
            expectedTitle: CommandLine.arguments[2],
            pressMatchedButton: CommandLine.arguments[1] == "open-title-button",
            temporaryValue: CommandLine.arguments[1] == "test-title-field"
                ? CommandLine.arguments[3] : nil,
            keyboardValue: CommandLine.arguments[1] == "test-title-keyboard"
                ? CommandLine.arguments[3] : nil,
            raiseTarget: CommandLine.arguments[1] == "raise-target-window",
            roundTrip: CommandLine.arguments[1] == "rename-and-restore"
                ? CommandLine.arguments[3] : nil)
        return
    }
    let seconds = CommandLine.arguments.count > 1
        ? min(900, max(0, Int(CommandLine.arguments[1]) ?? 0)) : 900
    log("probe-version=8 trusted=\(AXIsProcessTrusted()) seconds=\(seconds)")
    guard AXIsProcessTrusted() else { log("blocked: accessibility permission"); return }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
    }) else { log("blocked: ChatGPT app not running"); return }
    let pid = app.processIdentifier
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 0.6)
    // The original working helper used this Chromium AX opt-in. This can
    // enable accessibility metadata, but never edits conversation content.
    let before = read(root, "AXEnhancedUserInterface") as? NSNumber
    let enhanced = AXUIElementSetAttributeValue(
        root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    let after = read(root, "AXEnhancedUserInterface") as? NSNumber
    log("ax-enhanced-ui status=\(enhanced.rawValue) before=\(before?.boolValue.description ?? "unknown") after=\(after?.boolValue.description ?? "unknown")")
    // Official Electron guidance for external macOS accessibility tools:
    // set AXManualAccessibility on the application element.
    let manual = AXUIElementSetAttributeValue(
        root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    let manualAfter = read(root, "AXManualAccessibility") as? NSNumber
    log("ax-manual-accessibility status=\(manual.rawValue) after=\(manualAfter?.boolValue.description ?? "unknown")")
    Thread.sleep(forTimeInterval: 1.0)
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
