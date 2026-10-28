import AppKit
import ApplicationServices

// Uses only verified native UI actions: ChatGPT File > New Window,
// followed by ChatGPT Dock Recent > second More > unique exact title.
// No Electron Inspector, binary patching, or message submission.
final class DockRecentWindowRestorer {
    private var busy = false

    private func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result)
                == .success else { return nil }
        return result
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (read(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    private func str(_ element: AXUIElement, _ key: String) -> String {
        (read(element, key) as? String) ?? ""
    }
    private func winList(_ root: AXUIElement) -> [AXUIElement] {
        (read(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    private func title(_ win: AXUIElement) -> String {
        str(win, kAXTitleAttribute)
    }
    private func press(_ item: AXUIElement) -> Bool {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(item, &raw) == .success,
              ((raw as? [String]) ?? []).contains(kAXPressAction as String)
        else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString)
            == .success
    }

    private func dockRecentMatches(_ desired: String) -> [AXUIElement]? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let icons = children(root).flatMap { children($0) }.filter {
            str($0, kAXRoleAttribute) == "AXDockItem" &&
                str($0, kAXSubroleAttribute) == "AXApplicationDockItem" &&
                str($0, kAXTitleAttribute) == "ChatGPT"
        }
        guard icons.count == 1 else { return nil }
        var menu = children(icons[0]).first {
            str($0, kAXRoleAttribute) == "AXMenu"
        }
        if menu == nil {
            guard AXUIElementPerformAction(
                icons[0], kAXShowMenuAction as CFString) == .success
            else { return nil }
            // Dock adds the menu as a child asynchronously.
            Thread.sleep(forTimeInterval: 0.35)
            menu = children(icons[0]).first {
                str($0, kAXRoleAttribute) == "AXMenu"
            }
        }
        guard let menu else { return nil }
        let more = children(menu).filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == "More"
        }
        guard more.count == 2 else { return nil }
        let nested = children(more[1]).filter {
            str($0, kAXRoleAttribute) == "AXMenu"
        }
        guard nested.count == 1 else { return nil }
        return children(nested[0]).filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == desired
        }
    }

    private func fileNewWindow(_ root: AXUIElement) -> AXUIElement? {
        guard let bar = read(root, kAXMenuBarAttribute),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let top = children(bar as! AXUIElement).filter {
            str($0, kAXTitleAttribute) == "파일"
        }
        guard top.count == 1 else { return nil }
        let items = children(top[0]).flatMap { children($0) }.filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == "새 창"
        }
        guard items.count == 1,
              (read(items[0], kAXEnabledAttribute) as? NSNumber)?.boolValue == true
        else { return nil }
        return items[0]
    }

    // Explicit one-shot, non-navigating diagnostic. Invoked only by the
    // signed helper with TITLEHELPER_SAFE_BLANK_PROBE=1 at launch.
    // Never closes, unminimizes, navigates or edits an existing conversation.
    func probeBlankWindow(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "busy-or-no-AX-permission"); return }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil
        else { completed(false, "preflight-window-or-menu-unsafe"); return }

        // Fail closed if any original window cannot report minimized state.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "preflight-minimized-unavailable"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }
        let priorFrontmost = NSWorkspace.shared.frontmostApplication
        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "activation-request-rejected")
            return
        }

        // The previous test pressed File > New Window immediately after
        // activation and saw AXPress success but no new window. Wait for
        // confirmed focus, then resolve the menu item again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focus-not-confirmed")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focused-menu-or-AXPress-failed")
                return
            }
            let startedAt = ProcessInfo.processInfo.systemUptime
            func poll() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        poll()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                let newGeneric = created.count == 1 &&
                    self.title(created[0]) == "ChatGPT"
                let success = after.count == original.count + 1 &&
                    created.count == 1 && originalsRetained && newGeneric
                self.busy = false
                // Restore the prior app focus, never close any window.
                if let priorFrontmost,
                   priorFrontmost.processIdentifier != app.processIdentifier {
                    _ = priorFrontmost.activate()
                }
                completed(success, "before=\(original.count) after=\(after.count) " +
                    "created=\(created.count) originalsRetained=\(originalsRetained) " +
                    "newGeneric=\(newGeneric) elapsed=\(Int(elapsed))s")
            }
            poll()
        }
    }


    // Search Chats is a hidden native accelerator in the installed ChatGPT
    // build (visible=false), not a File-menu AXMenuItem. Probe the visible
    // sidebar Search AXButton on an independently verified new window only.
    private func searchUIScan(_ window: AXUIElement)
        -> (buttons: [AXUIElement], inputs: Int, dialogs: Int, limited: Bool,
            visitedCount: Int, elapsedMs: Int, remainingCount: Int) {
        let allowed: Set<String> = [
            "search", "search chats", "search chats…", "search conversations",
            "검색", "채팅 검색", "채팅 검색…", "대화 검색", "대화 검색…"
        ]
        var queue: [AXUIElement] = [window]
        var visited: Set<String> = []
        var buttons: [AXUIElement] = []
        var inputs = 0
        var dialogs = 0
        var index = 0
        let started = ProcessInfo.processInfo.systemUptime
        // Search the full AX subtree. Stop only on the monotonic time budget,
        // never on an arbitrary element count or per-parent child cap.
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            let key = String(CFHash(element))
            guard visited.insert(key).inserted else { continue }
            let role = str(element, kAXRoleAttribute)
            if role == "AXTextField" || role == "AXSearchField" ||
                role == "AXComboBox" { inputs += 1 }
            if role == "AXDialog" || role == "AXSheet" { dialogs += 1 }
            if role == "AXButton" {
                let labels = [
                    str(element, kAXTitleAttribute),
                    str(element, kAXDescriptionAttribute),
                    str(element, kAXHelpAttribute)
                ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                          .lowercased() }
                if labels.contains(where: { allowed.contains($0) }) {
                    buttons.append(element)
                }
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let timedOut = index < queue.count && elapsed >= 5.0
        return (buttons, inputs, dialogs, timedOut,
            visited.count, Int(elapsed * 1000), queue.count - index)
    }

    // Opt-in read-only probe of one previously identity-verified blank window.
    // The caller supplies the exact complete native AX census (hash:minimized).
    // Fail closed on any changed window, missing identity or unexpected state.
    func probeIsolatedWindowMetrics(
        expectedID: String, expectedSnapshot: String,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "no-AX-or-app"); return }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "invalid-expected-snapshot"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "expected-baseline-not-eight-or-three"); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.35)
        let windows = winList(root)
        guard windows.count == expected.count else {
            completed(false, "window-count-changed"); return
        }
        var actual: [String: Bool] = [:]
        for window in windows {
            let id = String(CFHash(window))
            guard actual[id] == nil,
                  let minimized = (read(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue,
                  str(window, kAXRoleAttribute) == "AXWindow" else {
                completed(false, "window-identity-or-state-unavailable"); return
            }
            actual[id] = minimized
        }
        guard actual == expected,
              let target = windows.first(where: {
                  String(CFHash($0)) == expectedID
              }),
              title(target) == "ChatGPT" else {
            completed(false, "baseline-changed-or-target-not-generic"); return
        }
        // Read only the isolated AX subtree. Never log labels, titles, IDs,
        // message text, query text, or URL. No AXPress or app activation.
        let scan = searchUIScan(target)
        let after = winList(root)
        var afterStates: [String: Bool] = [:]
        for window in after {
            let id = String(CFHash(window))
            guard afterStates[id] == nil,
                  let minimized = (read(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue else {
                completed(false, "postscan-window-state-unavailable"); return
            }
            afterStates[id] = minimized
        }
        let preserved = afterStates == expected
        completed(preserved && !scan.limited,
            "isolated=true count=\(windows.count) minimized=3 " +
            "visited=\(scan.visitedCount) elapsedMs=\(scan.elapsedMs) " +
            "remaining=\(scan.remainingCount) limited=\(scan.limited) " +
            "searchButtons=\(scan.buttons.count) inputs=\(scan.inputs) " +
            "dialogs=\(scan.dialogs) originalsPreserved=\(preserved)")
    }

    // Explicit one-shot Search UI press on the previously verified eighth window.
    // Requires an exact eight-window census, a fixed ChatGPT PID and the target
    // already focused. No activation, AXRaise, text input or result selection.
    func probeIsolatedSearchPress(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "busy-AX-or-pid-changed"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func baselineSafe() -> (Bool, AXUIElement?) {
            let windows = self.winList(root)
            guard windows.count == 8 else { return (false, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      self.str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (self.read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (false, nil) }
                actual[id] = minimized
            }
            guard actual == expected,
                  let target = windows.first(where: {
                      String(CFHash($0)) == expectedID
                  }), self.title(target) == "ChatGPT" else {
                return (false, nil)
            }
            return (true, target)
        }
        guard baselineSafe().0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID,
              let rawFocused = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocused) == AXUIElementGetTypeID(),
              String(CFHash(rawFocused as! AXUIElement)) == expectedID,
              let target = baselineSafe().1 else {
            completed(false, "baseline-or-target-focus-changed"); return
        }
        let scan = searchUIScan(target)
        guard !scan.limited, scan.buttons.count == 1,
              scan.inputs == 0, scan.dialogs == 0,
              baselineSafe().0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID,
              let rawFocusAgain = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocusAgain) == AXUIElementGetTypeID(),
              String(CFHash(rawFocusAgain as! AXUIElement)) == expectedID else {
            completed(false, "search-button-or-prepress-guard-failed"); return
        }
        busy = true
        guard press(scan.buttons[0]) else {
            busy = false
            completed(false, "isolated-search-AXPress-failed"); return
        }
        let started = ProcessInfo.processInfo.systemUptime
        func poll() {
            let safe = baselineSafe().0
            guard safe else {
                self.busy = false
                completed(false, "postpress-window-census-changed"); return
            }
            let after = self.searchUIScan(target)
            let opened = !after.limited &&
                (after.inputs > scan.inputs || after.dialogs > scan.dialogs)
            if !opened && !after.limited &&
                ProcessInfo.processInfo.systemUptime - started < 6.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() }
                return
            }
            self.busy = false
            completed(opened,
                "isolatedSearchPressed=true opened=\(opened) " +
                "beforeInputs=\(scan.inputs) afterInputs=\(after.inputs) " +
                "beforeDialogs=\(scan.dialogs) afterDialogs=\(after.dialogs) " +
                "AXLimited=\(after.limited) originalsPreserved=\(safe)")
        }
        poll()
    }

    // Explicit opt-in, read-only measurement of the *currently focused*
    // ChatGPT AXWindow. It never creates/navigates/raises/closes a window,
    // enters a search query, or logs private titles, IDs, or contents.
    func probeFocusedSearchMetrics(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "no-AX-or-app"); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                app.processIdentifier else {
            completed(false, "ChatGPT-not-frontmost"); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.35)
        let originals = winList(root)
        let ids = originals.map { String(CFHash($0)) }
        guard !originals.isEmpty, Set(ids).count == originals.count,
              let rawFocused = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
            completed(false, "window-census-or-focus-unavailable"); return
        }
        let focused = rawFocused as! AXUIElement
        let focusedID = String(CFHash(focused))
        guard ids.contains(focusedID),
              (read(focused, kAXMinimizedAttribute) as? NSNumber)?.boolValue == false
        else { completed(false, "focused-window-not-eligible"); return }
        let beforeMinimized = originals.map {
            (read($0, kAXMinimizedAttribute) as? NSNumber)?.boolValue
        }
        guard beforeMinimized.allSatisfy({ $0 != nil }) else {
            completed(false, "minimized-state-unavailable"); return
        }
        let focusedRole: String
        if let rawFocus = read(root, kAXFocusedUIElementAttribute),
           CFGetTypeID(rawFocus) == AXUIElementGetTypeID() {
            focusedRole = str(rawFocus as! AXUIElement, kAXRoleAttribute)
        } else {
            focusedRole = "unavailable"
        }
        // The focused palette can be in a different native window than the
        // historical test window. Inspect only AX roles/ownership; no labels.
        let nativeKind = title(focused) == "ChatGPT" ? "generic" :
            (title(focused).isEmpty ? "empty" : "named")
        let genericWindows = originals.filter { title($0) == "ChatGPT" }.count
        let focusedIndex = ids.firstIndex(of: focusedID) ?? -1
        var focusedUIWindowMatched = false
        var focusedParentWindowMatched = false
        var focusedParentDepth = 0
        if let rawUI = read(root, kAXFocusedUIElementAttribute),
           CFGetTypeID(rawUI) == AXUIElementGetTypeID() {
            let ui = rawUI as! AXUIElement
            if let rawOwner = read(ui, kAXWindowAttribute),
               CFGetTypeID(rawOwner) == AXUIElementGetTypeID() {
                focusedUIWindowMatched = String(CFHash(rawOwner)) == focusedID
            }
            var current = ui
            var seen = Set<String>()
            // Parent-only chain: never enumerate private message descendants.
            while focusedParentDepth < 24 {
                let key = String(CFHash(current))
                guard seen.insert(key).inserted else { break }
                if key == focusedID {
                    focusedParentWindowMatched = true
                    break
                }
                AXUIElementSetMessagingTimeout(current, 0.2)
                guard let rawParent = read(current, kAXParentAttribute),
                      CFGetTypeID(rawParent) == AXUIElementGetTypeID()
                else { break }
                current = rawParent as! AXUIElement
                focusedParentDepth += 1
            }
        }
        let scan = searchUIScan(focused)
        let after = winList(root)
        let statesPreserved = after.count == originals.count &&
            after.map({ String(CFHash($0)) }) == ids &&
            after.enumerated().allSatisfy { i, item in
                (read(item, kAXMinimizedAttribute) as? NSNumber)?.boolValue ==
                    beforeMinimized[i]
            }
        completed(statesPreserved,
            "windowCount=\(originals.count) focusedRole=\(focusedRole) " +
            "visited=\(scan.visitedCount) elapsedMs=\(scan.elapsedMs) " +
            "remaining=\(scan.remainingCount) timedOut=\(scan.limited) " +
            "searchButtons=\(scan.buttons.count) inputs=\(scan.inputs) " +
            "dialogs=\(scan.dialogs) windowsPreserved=\(statesPreserved) " +
            "nativeKind=\(nativeKind) genericWindows=\(genericWindows) " +
            "focusedIndex=\(focusedIndex) minimizedWindows=\(beforeMinimized.filter { $0 == true }.count) " +
            "uiWindowMatched=\(focusedUIWindowMatched) " +
            "parentWindowMatched=\(focusedParentWindowMatched) " +
            "parentDepth=\(focusedParentDepth)")
    }

    private func probeSearchOnNewWindow(
        root: AXUIElement, app: NSRunningApplication,
        created: AXUIElement, originals: [AXUIElement],
        originalMinimized: [String: Bool],
        priorFrontmost: NSRunningApplication?,
        completed: @escaping (Bool, String) -> Void
    ) {
        let newID = String(CFHash(created))
        func finish(_ success: Bool, _ reason: String) {
            self.busy = false
            if let priorFrontmost,
               priorFrontmost.processIdentifier != app.processIdentifier {
                _ = priorFrontmost.activate()
            }
            completed(success, reason)
        }
        func originalsSafe() -> Bool {
            let after = self.winList(root)
            guard after.count == originals.count + 1,
                  after.contains(where: { String(CFHash($0)) == newID })
            else { return false }
            return originals.allSatisfy { old in
                let key = String(CFHash(old))
                guard let live = after.first(where: {
                    String(CFHash($0)) == key
                }), let minimized = self.read(
                    live, kAXMinimizedAttribute) as? NSNumber
                else { return false }
                return minimized.boolValue == originalMinimized[key]
            }
        }
        func newWindowFocused() -> Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier,
                  let raw = self.read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID()
            else { return false }
            let focused = raw as! AXUIElement
            return String(CFHash(focused)) == newID
        }
        let started = ProcessInfo.processInfo.systemUptime
        func waitForSearchButton() {
            guard originalsSafe(), self.title(created) == "ChatGPT",
                  newWindowFocused() else {
                finish(false, "search-preflight-window-focus-or-originals-changed")
                return
            }
            let scan = self.searchUIScan(created)
            guard !scan.limited else {
                finish(false, "search-button-AX-scan-limited")
                return
            }
            if scan.buttons.isEmpty &&
               ProcessInfo.processInfo.systemUptime - started < 6.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    waitForSearchButton()
                }
                return
            }
            guard scan.buttons.count == 1 else {
                finish(false, "search-button-count=\(scan.buttons.count)")
                return
            }
            guard self.press(scan.buttons[0]) else {
                finish(false, "search-button-AXPress-failed")
                return
            }
            let pressedAt = ProcessInfo.processInfo.systemUptime
            func verifySearchUI() {
                guard originalsSafe(), newWindowFocused() else {
                    finish(false, "search-after-press-window-or-focus-changed")
                    return
                }
                let after = self.searchUIScan(created)
                let visible = after.inputs > scan.inputs ||
                    after.dialogs > scan.dialogs
                if !visible && !after.limited &&
                   ProcessInfo.processInfo.systemUptime - pressedAt < 6.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        verifySearchUI()
                    }
                    return
                }
                finish(visible && !after.limited,
                    "search-UI-only opened=\(visible) " +
                    "inputsBefore=\(scan.inputs) inputsAfter=\(after.inputs) " +
                    "dialogsBefore=\(scan.dialogs) dialogsAfter=\(after.dialogs) " +
                    "originalsRetained=true AXLimited=\(after.limited)")
            }
            verifySearchUI()
        }
        // Give the new blank window's renderer time to expose its sidebar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            waitForSearchButton()
        }
    }

    // Explicit one-shot Search UI-only probe; no query or result selection.
    func probeSearchUI(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "busy-or-no-AX-permission"); return }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil
        else { completed(false, "preflight-window-or-menu-unsafe"); return }

        // Fail closed if any original window cannot report minimized state.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "preflight-minimized-unavailable"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }
        let priorFrontmost = NSWorkspace.shared.frontmostApplication
        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "activation-request-rejected")
            return
        }

        // The previous test pressed File > New Window immediately after
        // activation and saw AXPress success but no new window. Wait for
        // confirmed focus, then resolve the menu item again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focus-not-confirmed")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focused-menu-or-AXPress-failed")
                return
            }
            let startedAt = ProcessInfo.processInfo.systemUptime
            func poll() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        poll()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                let newGeneric = created.count == 1 &&
                    self.title(created[0]) == "ChatGPT"
                let success = after.count == original.count + 1 &&
                    created.count == 1 && originalsRetained && newGeneric
                guard success else {
                    self.busy = false
                    if let priorFrontmost,
                       priorFrontmost.processIdentifier != app.processIdentifier {
                        _ = priorFrontmost.activate()
                    }
                    completed(false, "new-window-failed before=\(original.count) " +
                        "after=\(after.count) created=\(created.count) " +
                        "retained=\(originalsRetained) generic=\(newGeneric)")
                    return
                }
                // Only the exact newly created generic window may receive Search.
                // No query, selection, clipboard, or owner conversation navigation.
                self.probeSearchOnNewWindow(root: root, app: app,
                    created: created[0], originals: original,
                    originalMinimized: originalMinimized,
                    priorFrontmost: priorFrontmost, completed: completed)
            }
            poll()
        }
    }

    func restore(title: String, completed: @escaping (Bool, String) -> Void) {
        guard !busy else { completed(false, "복원 작업 진행 중"); return }
        guard !title.isEmpty, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "ChatGPT 또는 접근성 권한 없음"); return }
        // Duplicate titles are ambiguous. Preflight before creating a window.
        guard let matches = dockRecentMatches(title), matches.count == 1 else {
            completed(false, "Recent에 없거나 같은 제목이 여러 개임")
            return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil else {
            completed(false, "복원 전 창/파일 메뉴 식별 실패")
            return
        }
        // Never navigate a new window if an existing window disappeared or
        // changed its minimized state during the creation preflight.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "기존 창 상태 식별 실패"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }

        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "ChatGPT 활성화 실패")
            return
        }
        // The live blank-window probe proved immediate AXPress after activate
        // can return success without creating a window. Wait for focus and
        // resolve a fresh menu item; press exactly once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                completed(false, "ChatGPT 포커스 확인 실패")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                completed(false, "새 창 메뉴 실행 실패")
                return
            }

            let createdAt = ProcessInfo.processInfo.systemUptime
            func waitForNewWindow() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - createdAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        waitForNewWindow()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                guard after.count == original.count + 1,
                      created.count == 1, originalsRetained,
                      self.title(created[0]) == "ChatGPT" else {
                    self.busy = false
                    completed(false, "새 빈 창/기존 창 보존 확인 실패")
                    return
                }

                // Re-read the Dock menu: preflight handles may be stale.
                guard let choices = self.dockRecentMatches(title),
                      choices.count == 1, self.press(choices[0]) else {
                    self.busy = false
                    completed(false, "새 창은 열렸지만 Recent 항목 실행 실패")
                    return
                }
                // Loading a native conversation title can take many seconds.
                let startedAt = ProcessInfo.processInfo.systemUptime
                let expectedCount = original.count + 1
                let newID = String(CFHash(created[0]))
                func checkResult() {
                    let result = self.winList(root)
                    let matched = result.contains {
                        String(CFHash($0)) == newID && self.title($0) == title
                    }
                    let retained = original.allSatisfy { old in
                        let key = String(CFHash(old))
                        guard let live = result.first(where: {
                            String(CFHash($0)) == key
                        }), let minimized = self.read(
                            live, kAXMinimizedAttribute) as? NSNumber
                        else { return false }
                        return minimized.boolValue == originalMinimized[key]
                    }
                    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                    let decision = WindowRestoreVerificationPolicy.decide(
                        elapsed: elapsed, expectedCount: expectedCount,
                        actualCount: result.count, newWindowTitleMatched: matched,
                        originalsRetained: retained)
                    switch decision {
                    case .pending:
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + WindowRestoreVerificationPolicy.pollSeconds
                        ) { checkResult() }
                    case .success:
                        self.busy = false
                        completed(true, "새 창으로 복원됨")
                    case .failure:
                        self.busy = false
                        completed(false, "복원 확인 시간 초과 " +
                            "windows=\(result.count)/\(expectedCount) " +
                            "targetMatched=\(matched) originalsRetained=\(retained)")
                    }
                }
                checkResult()
            }
            waitForNewWindow()
        }
    }
}
